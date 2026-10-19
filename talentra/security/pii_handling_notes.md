# PII Handling Notes — Talentra

**Document ID:** B81-PII  
**Version:** 1.0  
**Date:** 2026-10-20  
**Status:** Panel-Ready  

This document catalogues every column or table in the Talentra schema that holds personally identifiable information (PII), sensitive data, or internal financial data. For each item it records the sensitivity class, how the value is stored, any masking applied in the API or UI layer, and the applicable retention period.

Sensitivity classes used throughout this document:

| Class | Meaning |
|---|---|
| **Sensitive** | Could directly enable account compromise or identity theft (passwords, secrets, DOB, tax IDs). |
| **Personal** | Identifies or contacts a natural person (name, phone, email, IP address, device fingerprint). |
| **Internal** | Business-operational data that is not personally identifying but is still non-public. |

---

## Module: Administration

This module covers authentication, authorisation, consent, and audit infrastructure.  
Source tables: `credential`, `consent_record`, `audit_log`, `app_session`, `app_role`, `permission`, `role_permission`, `app_user_role`.

- **`credential.password_hash`** — **Sensitive**  
  bcrypt / argon2id hash of the user's password. The original plaintext password is **never** stored in the database. The hash is one-way: even the application cannot recover the original. The `hash_algorithm` column records which algorithm was used (currently `argon2id`). Password verification is performed entirely in the application layer by comparing the submitted plaintext against the stored hash.

- **`credential.totp_secret`** — **Sensitive**  
  If TOTP two-factor authentication is enabled, the shared secret is AES-256 encrypted at the application layer before being written to the database. The database stores only the ciphertext. The encryption key is managed outside the database (e.g., a secrets manager or HSM). This column is not present in the v1 DDL but is reserved for the TOTP roadmap item.

- **`consent_record.ip_address`** — **Personal**  
  The IP address from which the user gave or withdrew consent is stored as PostgreSQL `inet` type. It is required for legal compliance under DPDP Act 2023 and GDPR (proof of consent). The table is **append-only** (enforced by `sp_make_append_only`): rows can never be updated or deleted in the normal flow. Retention: **7 years** from the date of recording.

- **`audit_log`** — **Internal**  
  Append-only log (enforced by trigger). Contains `actor_app_user_id` (a foreign key to `app_user`, not a name or email), `action_code`, `entity_table`, `entity_id`, and JSONB snapshots of `old_data` / `new_data`. No free-form PII is written into these JSONB fields — the application layer is responsible for redacting sensitive fields before writing. The actor ID alone is not personally identifying without a join to `app_user`.

- **`app_session.session_token_hash`** — **Sensitive**  
  The session token issued to the client is **never** stored in the database. Only a SHA-256 hash of the token is persisted in `session_token_hash`. This means a database read cannot be directly replayed to impersonate a user — the attacker would need to invert a SHA-256 hash, which is computationally infeasible for a 256-bit random token.

---

## Module: Candidate Profile

Source tables: `candidate_profile`, `resume_version`, `privacy_setting`.

- **`candidate_profile.full_name`** — **Personal**  
  Stored in cleartext to support recruiter search and display. In server-side logs the value is masked to `First L.` (first name + last initial only). The full value is returned in API responses only to recruiters who have performed a paid profile download; non-downloading recruiters see the truncated form.

- **`candidate_profile.phone_e164`** — **Personal**  
  Stored in cleartext in E.164 format (e.g., `+919876543210`). Required so recruiters can contact candidates after a download. In API responses to recruiters who have **not** downloaded the profile, the field is masked to show only the last 4 digits: `+91-XXXX-XXXX-3210`. Candidates always see their own number in full.

- **`candidate_profile.contact_email`** — **Personal**  
  Stored in cleartext; used for transactional notifications (application updates, invitations). In API responses to non-downloading recruiters the local-part is replaced with asterisks and only the domain is returned: `****@example.com`. Candidates always see their own email in full.

- **`candidate_profile.date_of_birth`** — **Sensitive**  
  Stored in cleartext as a `date`. Age is computed at query time (`EXTRACT(year FROM age(date_of_birth))`). Because date of birth combined with name is a strong re-identification vector, this field is included in the right-to-erasure workflow: it is purged (set to NULL or the row deleted) within 30 days of an account deletion request.

- **`resume_version.file_reference`** — **Personal**  
  Stores only a path or URL to the object in external object storage (e.g., S3 / GCS). The actual resume binary is **never** stored in PostgreSQL. Access to the object-storage URL is governed by pre-signed URLs with short TTLs (recommended: 15 minutes), generated by the application layer on demand. The database path alone does not expose the file.

---

## Module: Organisation

Source tables: `organisation`, `organisation_identifier`.

- **`organisation_identifier.value`** — **Sensitive** (for tax / national registration IDs)  
  Currently stored in cleartext. This field may hold CIN, GSTIN, PAN, or equivalent identifiers depending on the `identifier_type`. **Recommendation (roadmap):** encrypt this column at the application layer with an organisation-scoped key. The verification token returned by the identity service is the operational reference and does not need to be decrypted for day-to-day use.

- **`organisation.contact_email`**, **`organisation.contact_phone`** — **Internal**  
  Stored in cleartext. These are organisational contact points, not personal contacts of natural persons. Standard access-control at the API layer prevents public enumeration.

---

## Module: Gig Marketplace

Source tables: `gig_worker_profile`, `gig_earning_reference`.

- **`gig_earning_reference.amount`** — **Internal**  
  Stored as a numeric value in cleartext. This is a financial record of a platform transaction and is not personal data in the GDPR / DPDP sense. It is retained for 7 years as a financial record.

- **`gig_worker_profile.hourly_rate`** — **Internal**  
  Stored in cleartext. This is a rate the worker has chosen to advertise to clients; it is not sensitive.

---

## Module: Subscriptions & Payments

Source tables: `payment_order`, `wallet_ledger`, `invoice`.

- **`payment_order.gateway_reference`** — **Internal**  
  A tokenised reference returned by the payment gateway (e.g., Razorpay order ID, Stripe PaymentIntent ID). This is **not** card data, bank account data, or any PCI-DSS in-scope value. The actual payment instrument is managed entirely by the gateway; Talentra never sees or stores it.

- **`wallet_ledger`** — **Internal**  
  Append-only ledger of platform credit transactions. Amounts are stored in plaintext as integer credit units. This is an internal credits system, not a monetary account. The `idempotency_key` column prevents duplicate billing entries.

- **`invoice`** — **Internal**  
  Invoice metadata (amounts, line items, dates) stored in cleartext. Invoices reference `organisation_id`, not individual natural persons.

---

## Module: Notifications

Source tables: `notification`.

- **`notification.payload`** — **Internal**  
  Stores structured event metadata: entity IDs, status codes, and a short human-readable audit snippet (e.g., `"Application for Job #42 moved to INTERVIEW"`). The full message body is rendered by the notification service at delivery time and is not persisted. No free-form PII (names, emails, phone numbers) is written into this column.

---

## Module: Licences & Sessions

Source tables: `device`, `app_session`, `login_history`, `licence`, `seat`.

- **`device.device_fingerprint`** — **Personal**  
  The raw device fingerprint string is **hashed with SHA-256** before being stored in the `device_fingerprint` column (constraint `uq_device_user_fingerprint` enforces uniqueness on the hash). The original fingerprint is not stored. This prevents the database from being used to track a device across users or services.

- **`app_session.ip_address`** — **Personal**  
  Stored as `inet` for session security purposes (anomalous-location detection, brute-force protection). Masked in the UI (shown as a partial address, e.g., `192.168.x.x`). Retention: **purge 30 days after `expires_at`** (background job).

- **`login_history.ip_address`** — **Personal**  
  Stored as `inet` for security auditing (failed-login pattern detection, account-takeover investigation). The table is append-only. Retention: **90 days** from `occurred_at`, after which rows are deleted by a scheduled purge job.

---

## Summary Table

| Column | Table | Sensitivity Class | Storage | Masking | Retention |
|---|---|---|---|---|---|
| `password_hash` | `credential` | Sensitive | argon2id hash, never cleartext | N/A — never returned to client | Until account deletion |
| `totp_secret` | `credential` | Sensitive | AES-256 ciphertext (app layer) | N/A — never returned to client | Until account deletion |
| `ip_address` | `consent_record` | Personal | Cleartext `inet` | Not masked (legal record) | 7 years |
| `old_data`, `new_data` | `audit_log` | Internal | JSONB, PII-redacted by app | N/A — admin-only access | 7 years |
| `session_token_hash` | `app_session` | Sensitive | SHA-256 hash only | N/A — hash not useful to client | 30 days post-expiry |
| `full_name` | `candidate_profile` | Personal | Cleartext | Logs: `First L.`; non-downloading recruiters: first name only | Until right-to-erasure |
| `phone_e164` | `candidate_profile` | Personal | Cleartext E.164 | Non-downloading recruiter: last 4 digits visible | Until right-to-erasure |
| `contact_email` | `candidate_profile` | Personal | Cleartext | Non-downloading recruiter: domain only | Until right-to-erasure |
| `date_of_birth` | `candidate_profile` | Sensitive | Cleartext `date` | Not exposed in list APIs | Purged on account deletion |
| `file_reference` | `resume_version` | Personal | Path/URL only; file in object storage | Pre-signed URL with 15-min TTL | Per resume version lifecycle |
| `value` | `organisation_identifier` | Sensitive | Cleartext (encryption roadmap) | Not exposed in public APIs | Until org deletion |
| `contact_email`, `contact_phone` | `organisation` | Internal | Cleartext | Standard API auth | Until org deletion |
| `amount` | `gig_earning_reference` | Internal | Cleartext numeric | N/A | 7 years (financial) |
| `hourly_rate` | `gig_worker_profile` | Internal | Cleartext numeric | N/A | Until profile deletion |
| `gateway_reference` | `payment_order` | Internal | Gateway token (not card data) | N/A | 7 years (financial) |
| `amount`, `balance_after` | `wallet_ledger` | Internal | Cleartext integer credits | N/A | 7 years (financial) |
| `payload` | `notification` | Internal | Structured metadata, no PII body | N/A | 6 months |
| `device_fingerprint` | `device` | Personal | SHA-256 hash only | N/A — hash not reversible | Until device revocation |
| `ip_address` | `app_session` | Personal | Cleartext `inet` | Partial in UI (`x.x.x.x`) | 30 days post session expiry |
| `ip_address` | `login_history` | Personal | Cleartext `inet` | Not exposed in UI | 90 days from event |

---

*Last updated: 2026-10-20 | Owner: Platform Engineering | Review cycle: Annually or on schema change*
