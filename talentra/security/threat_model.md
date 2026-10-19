# Threat Model — Talentra

**Document ID:** B81-THREAT  
**Version:** 1.0  
**Date:** 2026-10-20  
**Status:** Panel-Ready  

This document describes the trust boundaries, actor model, attack surface, and the mitigations built into the Talentra PostgreSQL schema. It is intended for security reviewers, penetration testers, and panel judges assessing the hackathon submission.

---

## 1. Trust Boundary

### Architecture Diagram

```
                        ┌──────────────────────────────────────────────┐
  INTERNET              │           TALENTRA INFRASTRUCTURE            │
                        │                                              │
  ┌──────────┐          │  ┌────────────────┐    ┌───────────────────┐ │
  │  Client  │ ─HTTPS─► │  │ Load Balancer  │───►│   API Service     │ │
  │ (browser │          │  │ (TLS termination│    │  (Node / Python)  │ │
  │  /app)   │          │  └────────────────┘    └────────┬──────────┘ │
  └──────────┘          │                                 │            │
                        │                         Private subnet only  │
                        │                                 │            │
                        │                        ┌────────▼──────────┐ │
                        │                        │    PostgreSQL      │ │
                        │                        │  (port 5432)      │ │
                        │                        │  NOT public-facing │ │
                        │                        └───────────────────┘ │
                        └──────────────────────────────────────────────┘
```

**Key boundary rules:**

1. Port 5432 is bound to the private subnet interface only. No security group / firewall rule permits public internet access to PostgreSQL.
2. The only credential holder for the database is the API service. Client applications never receive or use a database connection string.
3. TLS is terminated at the load balancer. Internal traffic between the load balancer and API service travels over a private network.
4. The API service connects to PostgreSQL as one of three roles (`app_candidate`, `app_recruiter`, `app_admin`) depending on the authenticated user's application role. It sets `app.user_id` and (for recruiters) the recruiter's `organisation_id` is derived automatically by the DB function `fn_ctx_org_id()`.

---

## 2. Actors and DB Roles

The Talentra database defines three PostgreSQL roles. All three are **nologin** roles — no human or client application ever authenticates directly as these roles. The API service authenticates as a service account that has been granted membership in the appropriate role for each request.

| Actor | DB Role | Can Read | Can Write | RLS Scope |
|---|---|---|---|---|
| **Candidate** | `app_candidate` | Own `candidate_profile`; own `application` rows; `job` rows with status `published` | Own `application` (insert/update); own `candidate_profile` | RLS enforced on `candidate_profile`, `job`, `application` |
| **Recruiter** | `app_recruiter` | `candidate_profile` (not blocked, is searchable); own organisation's `job` rows; own organisation's `application` rows; own organisation's `wallet_ledger` | Own organisation's `job` rows; pipeline stage updates on own organisation's `application` | RLS enforced on `candidate_profile`, `job`, `application`, `wallet_ledger` |
| **Admin** | `app_admin` | All tables | All tables | No RLS (`USING (true)` policies bypass all row filters) |
| **System / Service** | `app_admin` (with `app.user_id` set) | All tables | All tables | Audit trail is mandatory; every write must produce an `audit_log` row |

> `app_candidate` and `app_recruiter` have been **explicitly revoked** from `wallet_ledger`, `audit_log`, `login_history`, and `consent_record` — these tables are administratively sensitive and candidates/recruiters cannot read or write them at all.

---

## 3. Attack Scenarios and Mitigations

### 3.1 Horizontal Privilege Escalation — Recruiter Reads Another Organisation's Data

**Scenario:** Recruiter at Org A manipulates an API parameter to read jobs, applications, or wallet ledger entries belonging to Org B.

**Mitigation:** Row-Level Security policies enforce organisation scoping at the database layer — independent of application logic:

- `p_job_recruiter`: `USING (organisation_id = fn_ctx_org_id())`
- `p_application_recruiter`: `USING (job_id IN (SELECT id FROM job WHERE organisation_id = fn_ctx_org_id()))`
- `p_wallet_ledger_recruiter`: `USING (wallet_id IN (SELECT id FROM wallet WHERE organisation_id = fn_ctx_org_id()))`

Even if the application layer is bypassed or has a bug, the database returns 0 rows for out-of-scope queries. `fn_ctx_org_id()` is marked `SECURITY DEFINER` and derives the organisation purely from the authenticated `app.user_id` — it cannot be overridden by a request parameter.

---

### 3.2 Candidate Enumeration by Phone / Email

**Scenario:** Attacker iterates phone numbers or email addresses via the search API to build a list of registered users.

**Mitigation:**
- RLS policy `p_candidate_profile_self` restricts `app_candidate` reads to `app_user_id = fn_ctx_user_id()`. Candidates cannot see other candidates' rows.
- For `app_recruiter`, the policy checks `privacy_setting.is_searchable` (defaults `true` when absent, allowing opt-out).
- Phone and email are masked in API responses to non-downloading recruiters (last 4 digits / domain only), reducing the utility of enumeration even if a list is obtained.
- Rate-limiting and CAPTCHA at the API layer are a complementary (application-layer) control.

---

### 3.3 Wallet Overdraft / Credit Fraud

**Scenario:** Attacker crafts requests that debit more credits than the wallet holds, driving `balance_credits` below zero.

**Mitigation:**
- `wallet` table has `CHECK (balance_credits >= 0)`. Any `UPDATE` that would produce a negative balance is rejected by PostgreSQL at the constraint level.
- `wallet_ledger` is append-only (`sp_make_append_only`). Historical entries cannot be modified to inflate the apparent balance.
- Debit entries use an `idempotency_key` unique constraint to prevent duplicate charging from retried requests.

---

### 3.4 Concurrent Session Limit Bypass

**Scenario:** User (or attacker who has stolen credentials) attempts to create more simultaneous sessions than the licence allows.

**Mitigation:**
- `BEFORE INSERT` trigger `trg_app_session_limit` executes `fn_check_session_limit()`.
- The function counts active sessions (`ended_at IS NULL AND expires_at > now()`) and raises an exception if the count equals or exceeds `licence.max_concurrent_sessions`.
- The seat lookup uses `SELECT ... FOR UPDATE` semantics to prevent TOCTOU races under concurrent logins from the same account.

---

### 3.5 Replay Attack on Payment

**Scenario:** A valid payment webhook or API response is replayed to credit a wallet multiple times.

**Mitigation:**
- `payment_order` has a `UNIQUE` constraint on `idempotency_key`. A replayed request with the same key is rejected at the database level (unique violation), regardless of application-layer retry logic.

---

### 3.6 Duplicate Profile Download Billing

**Scenario:** A bug or race condition causes the same profile download to be billed twice, deducting credits twice.

**Mitigation:**
- `wallet_ledger` entries include an `idempotency_key`. Duplicate inserts for the same download event produce a unique-constraint violation and are rolled back, ensuring exactly-once billing semantics.

---

### 3.7 SQL Injection via Application

**Scenario:** Attacker injects SQL through a user-controlled input field (search query, filter parameter).

**Mitigation:**
- The application layer uses parameterised queries exclusively (`psycopg` / `psycopg2` `%s` placeholders; never string concatenation or f-string formatting of SQL).
- Even if a parameterised query is somehow bypassed, RLS policies limit the blast radius to the data the authenticated role is permitted to see.
- `pg_stat_statements` and query logging are enabled in production to detect anomalous query patterns.

---

### 3.8 Device Limit Bypass Under Concurrent Logins

**Scenario:** A user (or attacker) registers more devices than the licence's `max_devices_per_seat` by sending concurrent device-registration requests.

**Mitigation:**
- `BEFORE INSERT OR UPDATE` trigger `trg_seat_limit` on the `seat` table uses `SELECT ... FOR UPDATE` to lock the licence row before counting, eliminating the TOCTOU window.
- The same pattern is applied to device registration: concurrent inserts serialise on the licence row lock, and the first insert that exceeds the limit raises a `check_violation` exception.

---

### 3.9 Audit Log Tampering

**Scenario:** A compromised service account or insider attempts to delete or modify `audit_log` rows to cover their tracks.

**Mitigation:**
- `sp_make_append_only('audit_log')` installs a trigger that raises an exception on any `UPDATE`, `DELETE`, or `TRUNCATE` against the `audit_log` table.
- Even `app_admin` cannot modify existing rows — the trigger fires before the operation regardless of the caller's role.
- For additional assurance, WAL-based replication to an isolated read replica can be used to maintain a copy that is physically separate from the primary.

---

### 3.10 Blocked Candidate Visibility

**Scenario:** A recruiter who has blocked a candidate can still see that candidate's profile via a direct API call.

**Mitigation:**
- RLS policy `p_candidate_profile_recruiter` includes a `NOT EXISTS` sub-query against `block_list`:
  ```sql
  AND NOT EXISTS (
    SELECT 1 FROM block_list b
    WHERE b.candidate_profile_id = candidate_profile.id
      AND b.organisation_id = fn_ctx_org_id()
      AND b.deleted_at IS NULL
  )
  ```
  This is evaluated at the database layer, so no application-layer filter is needed. A blocked candidate returns 0 rows even if the recruiter has the correct `candidate_profile_id`.

---

## 4. Password Hashing

- Passwords are **never** stored in the Talentra database. `credential.password_hash` stores the output of the argon2id (or bcrypt) hashing function applied to the plaintext password.
- The algorithm used is recorded in `credential.hash_algorithm` (default: `argon2id`), enabling future algorithm migration without breaking existing accounts.
- The database contains **no function** to verify a password. Verification is performed exclusively in the application layer:
  1. Application queries `credential.password_hash` for the user.
  2. Application calls `argon2.verify(password_hash, submitted_plaintext)` locally.
  3. The plaintext never travels to the database.
- **Access restriction:** `REVOKE SELECT ON credential FROM app_candidate, app_recruiter` — neither candidates nor recruiters can query the credential table. Only `app_admin` (the service account) can read hashes, and only for the purpose of the authentication flow.

---

## 5. Session Controls

### Session Lifecycle

```
Client presents token
        │
        ▼
API hashes token → SHA-256 → looks up app_session by session_token_hash
        │
        ├─ Not found → 401 Unauthorized
        │
        ├─ Found but expires_at ≤ now() → 401 Session Expired
        │
        ├─ Found but ended_at IS NOT NULL → 401 Session Revoked
        │
        └─ Found, active → request proceeds with app_user_id
```

### Session Fields

| Field | Purpose | Security note |
|---|---|---|
| `session_token_hash` | SHA-256 of the bearer token | Token itself never stored; DB breach does not leak valid tokens |
| `device_id` | Links session to a registered device | Revoked devices cannot create new sessions (trigger check) |
| `expires_at` | Hard expiry timestamp | Enforced both in trigger and application layer |
| `ended_at` | Set on explicit logout or admin revocation | Revocation is immediate and recorded in `audit_log` |
| `ip_address` | IP at session creation | Used for anomalous-location detection |

### Concurrency Control

The `BEFORE INSERT` trigger `trg_app_session_limit` reads `licence.max_concurrent_sessions` for the user's active licence and raises `check_violation` if the active session count meets or exceeds this limit. Because the trigger uses `SELECT ... FOR UPDATE` on the licence row, concurrent login attempts from the same account serialise correctly.

---

## 6. Audit Trail

### Append-Only Guarantee

`sp_make_append_only('audit_log')` installs a trigger function that:
- Raises `SQLSTATE 'P0001'` (`raise_exception`) on `UPDATE`.
- Raises `SQLSTATE 'P0001'` on `DELETE`.
- Raises `SQLSTATE 'P0001'` on `TRUNCATE`.

This means no role — including `app_admin` — can alter or remove an existing audit row through normal SQL.

### Row Structure

| Column | Type | Purpose |
|---|---|---|
| `actor_app_user_id` | `bigint` | FK to `app_user`; who performed the action |
| `action_code` | `varchar(60)` | Enumerated action (see below) |
| `entity_table` | `varchar(63)` | Table affected |
| `entity_id` | `bigint` | PK of the affected row |
| `old_data` | `jsonb` | Snapshot of the row before the change (PII-redacted) |
| `new_data` | `jsonb` | Snapshot of the row after the change (PII-redacted) |
| `occurred_at` | `timestamptz` | Timestamp of the action |

### Audited Action Codes

| Action Code | Trigger |
|---|---|
| `login` | Successful authentication |
| `logout` | Explicit session termination |
| `password_change` | `credential.password_hash` updated |
| `role_change` | `app_user_role` inserted or soft-deleted |
| `profile_download` | Recruiter downloads a candidate profile |
| `wallet_recharge` | `wallet_ledger` credit entry created |
| `subscription_create` | Subscription activated |
| `subscription_cancel` | Subscription cancelled |
| `device_register` | New `device` row inserted |
| `device_revoke` | `device.revoked_at` set |
| `block_candidate` | `block_list` row inserted |
| `unblock_candidate` | `block_list` row soft-deleted |

---

*Last updated: 2026-10-20 | Owner: Platform Engineering | Review cycle: Annually or on schema change*
