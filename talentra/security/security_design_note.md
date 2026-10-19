# Talentra — Security Design Note
> Deliverable B81 | Combines PII handling, threat model, RLS design, audit trail, and backup/restore RTO.
> References: `security/pii_handling_notes.md`, `security/threat_model.md`, `talentra_db/09_security_rls.sql`

---

## 1. Executive Summary

Talentra's security posture is built on three layers enforced at the database level — not just in application code.

**Layer 1: Role-based access control.** Three PostgreSQL roles (`app_candidate`, `app_recruiter`, `app_admin`) are defined in the database. Every connection from the application sets its role before executing queries. Roles cannot be escalated from within a query.

**Layer 2: Row-Level Security.** Four tables carry RLS policies enforced by PostgreSQL itself: `candidate_profile`, `job`, `application`, and `wallet_ledger`. A recruiter physically cannot retrieve rows from another organisation even with a correctly formed SELECT query — the database discards those rows before returning results. A candidate blocked by an organisation is invisible to that organisation's recruiters. These guarantees hold regardless of bugs in the application layer.

**Layer 3: Append-only audit and financial tables.** Triggers on `audit_log`, `wallet_ledger`, `login_history`, `consent_record`, and `application_history` block UPDATE, DELETE, and TRUNCATE at the database level. No application code, no service account, and no SQL mistake can silently alter these records. A correction to a ledger entry requires a new compensating entry — preserving full history.

Sensitive personal data (passwords, session tokens, device fingerprints) is never stored in cleartext. Credentials are hashed; tokens are stored as SHA-256 hashes; raw national identifiers should be encrypted at the application layer (noted as a known gap in v1).

---

## 2. Row-Level Security Design

### 2.1 DB Roles

| Role | Login | Intended user | Scope |
|---|---|---|---|
| `app_candidate` | No (set by app) | Authenticated candidate | Own rows only |
| `app_recruiter` | No (set by app) | Authenticated recruiter | Own organisation's rows only |
| `app_admin` | No (set by app) | Admin users and service accounts | All rows, no RLS |

The application sets the role and user context on each connection:
```sql
SET ROLE app_recruiter;
SET app.user_id = '12345';  -- authenticated user's app_user.id
```

Two helper functions read this context:
- `fn_ctx_user_id()` → returns the current `app.user_id` as `bigint`
- `fn_ctx_org_id()` → returns the `organisation_id` for the recruiter matching the current user

### 2.2 RLS Policies per Table

**`candidate_profile`**

| Role | Operation | Policy |
|---|---|---|
| `app_candidate` | ALL | `app_user_id = fn_ctx_user_id()` — only own row |
| `app_recruiter` | SELECT | `deleted_at IS NULL` AND `privacy_setting.is_searchable = true` AND NOT in `block_list` for their org |
| `app_admin` | ALL | `true` — no restriction |

**`job`**

| Role | Operation | Policy |
|---|---|---|
| `app_candidate` | SELECT | `deleted_at IS NULL` AND `job_status = 'published'` — only published jobs |
| `app_recruiter` | ALL | `organisation_id = fn_ctx_org_id()` — only their org's jobs |
| `app_admin` | ALL | `true` |

**`application`**

| Role | Operation | Policy |
|---|---|---|
| `app_candidate` | ALL | `candidate_profile_id IN (own profiles)` |
| `app_recruiter` | SELECT | `job_id IN (jobs where organisation_id = fn_ctx_org_id())` |
| `app_recruiter` | UPDATE | Same as SELECT |
| `app_admin` | ALL | `true` |

**`wallet_ledger`**

| Role | Operation | Policy |
|---|---|---|
| `app_candidate` | — | REVOKED entirely |
| `app_recruiter` | SELECT | `wallet_id IN (wallets for own org)` |
| `app_recruiter` | INSERT/UPDATE | REVOKED |
| `app_admin` | ALL | `true` |

### 2.3 Additional Revocations

```sql
REVOKE ALL ON wallet_ledger, audit_log, login_history, consent_record FROM app_candidate;
REVOKE INSERT, UPDATE ON wallet_ledger FROM app_recruiter;
```

Candidates cannot see any financial or audit data. Recruiters can read their organisation's ledger but cannot write to it.

---

## 3. PII Handling Summary

Full detail in `security/pii_handling_notes.md`. Key decisions:

| Column | Table | Sensitivity | Storage | Protection |
|---|---|---|---|---|
| `password_hash` | `credential` | Sensitive | Hashed (bcrypt/argon2) | Never stored in cleartext |
| `session_token_hash` | `app_session` | Sensitive | SHA-256 hash | Original token never stored |
| `totp_secret` | `credential` | Sensitive | AES-256 encrypted | Application-layer encryption |
| `device_fingerprint` | `device` | Personal | SHA-256 hash | Original never stored |
| `phone_e164` | `candidate_profile` | Personal | Cleartext | Masked in API for non-downloading recruiters |
| `contact_email` | `candidate_profile` | Personal | Cleartext | Masked (domain only) for non-downloading |
| `date_of_birth` | `candidate_profile` | Sensitive | Cleartext | Deletable on erasure request |
| `ip_address` | `app_session`, `login_history` | Personal | Cleartext | Masked in UI, short retention |
| `value` | `organisation_identifier` | Sensitive (tax IDs) | Cleartext ⚠️ | **Gap: should be encrypted at app layer** |
| `gateway_reference` | `payment_order` | Internal | Tokenised ref only | No card/bank data stored |

---

## 4. Audit Trail Design

The `audit_log` table records every sensitive action:

| Column | Type | Description |
|---|---|---|
| `id` | bigint identity | Immutable PK |
| `app_user_id` | bigint | Actor (nullable for system events) |
| `action_code` | varchar(60) | Event type: `login`, `logout`, `password_change`, `role_change`, `download`, `wallet_recharge`, `subscription_create`, `block_add`, `device_revoke`, etc. |
| `entity_table` | varchar(63) | Affected table |
| `entity_id` | bigint | Affected row ID |
| `old_value` | jsonb | Previous state (for updates) |
| `new_value` | jsonb | New state |
| `ip_address` | inet | Source IP |
| `created_at` | timestamptz | UTC timestamp — immutable |

**Append-only enforcement:** `sp_make_append_only('audit_log')` installs a BEFORE trigger that raises `restrict_violation` on UPDATE, DELETE, and TRUNCATE. No role in the database can bypass this without superuser privileges.

---

## 5. Backup and Restore RTO

### Current setup

| Scenario | Method | Est. dump time | Est. restore time | RTO target |
|---|---|---|---|---|
| Full backup at dev scale (~10K profiles) | `pg_dump -Fc` | < 30 sec | < 1 min | < 5 min |
| Full backup at 1M profiles | `pg_dump -Fc` | 2–5 min | 5–10 min | < 30 min |
| Full backup at 10M profiles | `pg_dump -Fc` | 20–50 min | 30–90 min | < 60 min (with WAL) |
| Incremental (WAL archiving via pgBackRest) | pgBackRest | Continuous | < 15 min to any point | < 15 min |

### backup_restore_test.sh

The script at `talentra_db/backup_restore_test.sh` performs:
1. `pg_dump -Fc talentra > talentra_backup.dump`
2. `createdb talentra_restore`
3. `pg_restore -d talentra_restore talentra_backup.dump`
4. Row count comparison on key tables (candidate_profile, application, wallet_ledger)
5. Prints dump time, restore time, and pass/fail for row count check

Run: `bash talentra_db/backup_restore_test.sh` — output goes to stdout and should be pasted into this table once run at 1M scale.

---

## 6. Session and Device Security

- Every session has: `session_token_hash` (SHA-256), `device_id`, `started_at`, `last_seen_at`, `expires_at`, `ended_at`
- **Active session:** `expires_at > NOW()` AND `ended_at IS NULL`
- **Concurrent limit:** enforced by a BEFORE INSERT trigger on `app_session`. It counts active sessions for the user's licence and raises `check_violation` if the count ≥ `licence.max_concurrent_sessions`. Uses `SELECT ... FOR UPDATE` on the licence row to prevent race conditions.
- **Revoking a device:** sets `device.revoked_at = NOW()` and writes to `audit_log` with `action_code = 'device_revoke'`. Existing sessions on that device are expired immediately.
- **Revoking a session:** sets `app_session.ended_at = NOW()` and writes to `audit_log`.

---

## 7. Known Gaps and Roadmap

| Gap | Risk | Recommended fix | Version |
|---|---|---|---|
| `organisation_identifier.value` (tax IDs) stored in cleartext | Medium — internal DB access exposes national IDs | Encrypt with AES-256 at application layer before INSERT | v1.1 |
| Social sharing events not modelled | Low — Tier 3 optional | Add `share_event` table if social integration built | v2 |
| Legacy sync quarantine table missing | Low — migration scope | Add `migration_rejected_row` table with source + reason | v2 |
| Full-text resume search would expose PII at scale | Medium | Separate Elasticsearch/OpenSearch index with field-level masking | v2 |
| `app.user_id` trusted from session config | Medium — requires app to set it correctly | Enforce via connection pool auth token | v1.1 |
| Credential table not separately encrypted | Low — already hashed | Enable PostgreSQL column-level encryption (pgcrypto) for totp_secret | v1.1 |

---

## 8. Compliance Checklist

| Requirement | How it is met |
|---|---|
| Recruiter sees only own org's data | RLS on `job`, `application`, `candidate_profile` |
| Blocked candidate invisible to blocker | RLS on `candidate_profile` joins `block_list` |
| Wallet cannot go negative | CHECK constraint + append-only ledger trigger |
| Subscription periods don't overlap | EXCLUDE USING GIST (added in 06b_schema_fixes.sql) |
| Gig windows don't overlap per worker | EXCLUDE USING GIST on `gig_assignment` |
| Passwords never retrievable | bcrypt/argon2 hash in `credential.password_hash` |
| Session tokens never in cleartext | SHA-256 hash in `app_session.session_token_hash` |
| Concurrent session limit enforced | BEFORE INSERT trigger on `app_session` |
| Audit log immutable | `sp_make_append_only('audit_log')` trigger |
| Ledger immutable | `sp_make_append_only('wallet_ledger')` trigger |
| Profile download idempotent | Idempotency key on `wallet_ledger` via `sp_download_profile()` |
| Data deletion on request (DPDP Act 2023) | soft delete + `deleted_at`; background purge process (app layer) |

---

*Last updated: October 2026 | Docket reference: B81*
