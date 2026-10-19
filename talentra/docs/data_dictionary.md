# Talentra — Data Dictionary
> Deliverable B56 / B66 | Sensitivity classes per column, by module.
> Source: `talentra_db/data_dictionary.csv` + schema review.
> Sensitivity classes: **Public** (no restriction), **Internal** (staff and owning org), **Personal** (identifies a person), **Sensitive** (national ID, credentials, payment refs — requires encryption/masking).

---

## Module 1: Core / Master Data

### `app_user`
*Single identity record for every person or system actor on the platform. All roles hang off this table.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate primary key |
| `email` | varchar(254) | No | Personal | Login email, unique, stored lowercase. Masked in analytics. |
| `display_name` | varchar(150) | No | Personal | Public display name. Masked in logs. |
| `is_active` | boolean | No | Internal | Whether the account is enabled |
| `created_at` | timestamptz | No | Internal | Row creation timestamp (UTC) |
| `created_by` | bigint | No | Internal | FK → app_user (audit) |
| `updated_at` | timestamptz | No | Internal | Last update timestamp (UTC) |
| `updated_by` | bigint | No | Internal | FK → app_user (audit) |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete timestamp. NULL = active. |

---

### `country`
*ISO 3166-1 country reference. Master data, loaded from GeoNames.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | char(2) | No | Public | ISO 3166-1 alpha-2 code (e.g. `'IN'`) |
| `name` | varchar(150) | No | Public | English country name |
| `phone_code` | varchar(10) | Yes | Public | International dialling code (e.g. `'+91'`) |

---

### `city`
*City reference with coordinates. Loaded from GeoNames.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `name` | varchar(150) | No | Public | City name |
| `state_id` | bigint | Yes | Public | FK → state |
| `country_id` | bigint | No | Public | FK → country |
| `latitude` | numeric(9,6) | Yes | Public | WGS-84 latitude |
| `longitude` | numeric(9,6) | Yes | Public | WGS-84 longitude |

---

### `skill`
*Skill taxonomy loaded from ESCO (European Skills/Competences/Qualifications and Occupations).*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | varchar(60) | No | Public | ESCO URI or internal code |
| `name` | varchar(200) | No | Public | English skill name |
| `is_active` | boolean | No | Public | Whether this skill is available in the UI |

---

### `job_role`
*Job role taxonomy (ESCO). Used to categorise jobs and candidate experience.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | varchar(60) | No | Public | ESCO/internal code |
| `name` | varchar(200) | No | Public | Role name (e.g. `'software_engineer'`) |

---

### `currency`
*ISO 4217 currency reference.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | char(3) | No | Public | ISO 4217 code (e.g. `'INR'`) |
| `name` | varchar(100) | No | Public | Currency name |
| `symbol` | varchar(10) | Yes | Public | Display symbol (e.g. `'₹'`) |

---

### `language`
*Language reference (ISO 639-1).*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | varchar(10) | No | Public | BCP-47 tag (e.g. `'en'`, `'hi'`) |
| `name` | varchar(100) | No | Public | English name |
| `is_default` | boolean | No | Public | True for `'en'` — used for fallback in UI translations |

---

## Module 2: Candidate Profile

### `candidate_profile`
*Core candidate record. One row per candidate user. Soft-deleted on account deletion request.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user |
| `full_name` | varchar(150) | No | Personal | Full name in any script (UTF-8) |
| `headline` | varchar(300) | Yes | Personal | Professional headline shown on profile cards |
| `phone_e164` | varchar(20) | Yes | Personal | Phone in E.164 format. Masked (last 4 only) for non-downloading recruiters. |
| `contact_email` | varchar(254) | Yes | Personal | Contact email (may differ from login email). Masked (domain only) for non-downloaders. |
| `city_id` | bigint | Yes | Internal | FK → city. Nullable: candidate may not share location. |
| `date_of_birth` | date | Yes | Sensitive | DOB. Nullable: not mandatory. Deleted on erasure request. |
| `total_experience_months` | integer | No | Internal | Computed/entered total experience in months |
| `expected_salary` | numeric(14,2) | Yes | Personal | Expected annual salary. Nullable: not all candidates disclose. |
| `expected_salary_currency_id` | bigint | Yes | Internal | FK → currency. Nullable: same reason as salary. |
| `notice_period_days` | integer | No | Internal | Notice period (0 = immediate) |
| `is_open_to_work` | boolean | No | Public | Whether recruiters should see this profile |
| `preferred_language_id` | bigint | Yes | Internal | FK → language. For notification localisation. |
| `profile_completeness` | numeric(5,2) | No | Internal | Computed 0–100 score |
| `linkedin_url` | varchar(300) | Yes | Personal | LinkedIn profile URL (optional) |
| `github_url` | varchar(300) | Yes | Personal | GitHub URL (optional) |
| `portfolio_url` | varchar(300) | Yes | Personal | Portfolio URL (optional) |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete |

---

### `candidate_skill`
*Many-to-many: which candidates have which skills, at what proficiency.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `skill_id` | bigint | No | Public | FK → skill |
| `skill_proficiency_id` | bigint | Yes | Internal | FK → skill_proficiency (beginner/intermediate/expert). Nullable: proficiency may not be stated. |
| `years_experience` | numeric(4,1) | Yes | Internal | Years of experience with this skill. Nullable. |

---

### `candidate_education`
*Education history. Multiple rows per candidate.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `qualification_id` | bigint | No | Internal | FK → qualification (degree type) |
| `institution` | varchar(300) | No | Personal | Institution name |
| `field_of_study` | varchar(200) | Yes | Personal | Major / specialisation. Nullable. |
| `start_date` | date | No | Personal | Start of study period |
| `end_date` | date | Yes | Personal | End of study period. Nullable = currently enrolled. |
| `grade` | varchar(50) | Yes | Internal | Grade/percentage/CGPA. Nullable. |

---

### `candidate_experience`
*Work experience history. Multiple rows per candidate.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `job_role_id` | bigint | Yes | Internal | FK → job_role |
| `employment_type_id` | bigint | Yes | Internal | FK → employment_type |
| `employer_name` | varchar(300) | No | Personal | Employer name as entered by candidate |
| `job_title` | varchar(300) | No | Personal | Job title as entered |
| `start_date` | date | No | Personal | Employment start |
| `end_date` | date | Yes | Personal | Employment end. Nullable = current job. |
| `is_current` | boolean | No | Internal | True if this is the current employer |
| `description` | text | Yes | Internal | Job description / achievements (unbounded — justified by content nature) |

---

### `resume_version`
*Resume file versions. Multiple versions per candidate. `is_primary` identifies the default.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `version_no` | integer | No | Internal | Version number (1, 2, 3…) |
| `file_reference` | varchar(500) | No | Personal | Path or object-storage URL. Actual file is NOT in the DB. |
| `is_primary` | boolean | No | Internal | True = currently active resume |

---

## Module 3: Jobs and Applications

### `job`
*Job requirement posted by an organisation. Soft-deleted.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `job_role_id` | bigint | Yes | Public | FK → job_role |
| `employment_type_id` | bigint | No | Public | FK → employment_type |
| `work_type_id` | bigint | No | Public | FK → work_type (remote/hybrid/on-site) |
| `job_status_id` | bigint | No | Internal | FK → job_status (draft/published/closed) |
| `city_id` | bigint | Yes | Public | FK → city. Nullable for fully remote. |
| `title` | varchar(300) | No | Public | Job title |
| `salary_min` | numeric(14,2) | Yes | Internal | Minimum salary. Nullable if not disclosed. |
| `salary_max` | numeric(14,2) | Yes | Internal | Maximum salary. Nullable if not disclosed. |
| `salary_currency_id` | bigint | Yes | Internal | FK → currency. Nullable if salary not disclosed. |
| `published_at` | timestamptz | Yes | Public | When posted. Nullable for drafts. |
| `expires_at` | timestamptz | Yes | Internal | When posting expires. |
| `description` | text | Yes | Public | Full job description (unbounded — justified by content nature) |
| `experience_min_years` | integer | Yes | Public | Minimum years required |
| `experience_max_years` | integer | Yes | Public | Maximum years preferred |
| `openings` | integer | No | Public | Number of open positions |
| `is_open_to_consultants` | boolean | No | Internal | Whether external consultants can source for this job |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete |

---

### `application`
*A candidate's application to a job. Partitioned-ready by applied_at.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `job_id` | bigint | No | Internal | FK → job |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `application_stage_id` | bigint | No | Internal | FK → application_stage (current stage) |
| `resume_version_id` | bigint | Yes | Internal | FK → resume_version. Nullable: candidate may not attach. |
| `cover_note` | varchar(2000) | Yes | Personal | Cover note (optional) |
| `expected_salary` | numeric(14,2) | Yes | Personal | Salary expectation at time of application. Nullable. |
| `applied_at` | timestamptz | No | Internal | Application submission timestamp |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete |

---

### `application_stage`
*Lookup: pipeline stages.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Public | Surrogate PK |
| `code` | varchar(60) | No | Public | `applied`, `shortlisted`, `interviewed`, `offered`, `joined`, `rejected`, `withdrawn` |
| `name` | varchar(100) | No | Public | Display name |
| `stage_order` | integer | No | Public | Sort order (lower = earlier in pipeline) |
| `is_terminal` | boolean | No | Internal | True for `joined`, `rejected`, `withdrawn` |

---

### `application_history`
*Immutable audit trail of every stage transition. Append-only.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `application_id` | bigint | No | Internal | FK → application |
| `from_stage_id` | bigint | Yes | Internal | Previous stage. Nullable for the first entry. |
| `to_stage_id` | bigint | No | Internal | New stage |
| `changed_by` | bigint | Yes | Internal | FK → app_user who changed the stage (nullable for system). |
| `changed_at` | timestamptz | No | Internal | Timestamp of the transition |

---

### `saved_job`
*Jobs bookmarked by a candidate.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile |
| `job_id` | bigint | No | Internal | FK → job |
| `saved_at` | timestamptz | No | Internal | When bookmarked |

---

## Module 4: Administration

### `app_role`
*Roles assignable to users (e.g. candidate, recruiter, admin).*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `code` | varchar(60) | No | Internal | Machine code (e.g. `'recruiter'`) |
| `name` | varchar(100) | No | Internal | Display name |
| `description` | varchar(500) | Yes | Internal | Nullable: not all roles need a description. |

---

### `credential`
*Login credentials. One row per user. NEVER stores plaintext passwords.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Sensitive | Surrogate PK |
| `app_user_id` | bigint | No | Sensitive | FK → app_user |
| `password_hash` | varchar(255) | Yes | Sensitive | bcrypt/argon2 hash. Nullable if using SSO only. NEVER cleartext. |
| `totp_secret` | varchar(255) | Yes | Sensitive | TOTP secret for 2FA. AES-256 encrypted. Nullable if 2FA not enabled. |
| `password_changed_at` | timestamptz | Yes | Internal | Last password change. Nullable for SSO users. |
| `failed_attempts` | integer | No | Internal | Consecutive failed login attempts (for lockout) |
| `locked_until` | timestamptz | Yes | Internal | Account lockout expiry. Nullable = not locked. |

---

### `app_session`
*Active user sessions. Session limit enforced by trigger.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user |
| `device_id` | bigint | Yes | Internal | FK → device. Nullable: session without registered device. |
| `session_token_hash` | varchar(255) | No | Sensitive | SHA-256 hash of the session token. Original never stored. |
| `ip_address` | inet | Yes | Personal | Source IP. Masked in UI. Retention: 30 days post-expiry. |
| `started_at` | timestamptz | No | Internal | Session start |
| `last_seen_at` | timestamptz | No | Internal | Last activity (used for idle timeout) |
| `expires_at` | timestamptz | No | Internal | Hard expiry |
| `ended_at` | timestamptz | Yes | Internal | Explicit logout or revocation. Nullable = active. |

---

### `device`
*Registered devices per user.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user |
| `device_name` | varchar(200) | Yes | Personal | User-given name (e.g. `'My MacBook'`). Nullable. |
| `device_fingerprint` | varchar(255) | No | Personal | SHA-256 hash of device attributes. Original never stored. |
| `registered_at` | timestamptz | No | Internal | When first registered |
| `revoked_at` | timestamptz | Yes | Internal | Revocation timestamp. Nullable = active. |

---

### `audit_log`
*Immutable audit trail of every sensitive action. Append-only (trigger blocks UPDATE/DELETE/TRUNCATE).*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | Yes | Internal | Actor. Nullable for system-initiated events. |
| `action_code` | varchar(60) | No | Internal | Event type: `login`, `download`, `wallet_recharge`, etc. |
| `entity_table` | varchar(63) | No | Internal | Affected table name |
| `entity_id` | bigint | Yes | Internal | Affected row ID. Nullable for bulk operations. |
| `old_value` | jsonb | Yes | Internal | Previous state snapshot. Nullable for inserts. |
| `new_value` | jsonb | Yes | Internal | New state snapshot. Nullable for deletes. |
| `ip_address` | inet | Yes | Personal | Source IP. Retention: 7 years (legal requirement). |
| `created_at` | timestamptz | No | Internal | Event timestamp (UTC). Immutable. |

---

### `consent_record`
*GDPR/DPDP Act consent records. Append-only.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Personal | FK → app_user |
| `consent_type` | varchar(60) | No | Internal | Type of consent (e.g. `'data_processing'`, `'marketing'`) |
| `is_granted` | boolean | No | Internal | Whether consent was given or withdrawn |
| `ip_address` | inet | Yes | Personal | Source IP at time of consent. Retention: 7 years. |
| `consented_at` | timestamptz | No | Internal | Timestamp of consent action |

---

## Module 5: Organisation

### `organisation`
*Employer or client company. Soft-deleted.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `name` | varchar(300) | No | Public | Company name |
| `industry_id` | bigint | Yes | Public | FK → industry. Nullable if industry unknown. |
| `country_id` | bigint | Yes | Public | FK → country. Nullable for global organisations. |
| `verification_status_id` | bigint | Yes | Internal | FK → verification_status |
| `parent_organisation_id` | bigint | Yes | Internal | FK → organisation (for org hierarchy). Nullable for root orgs. |
| `website_url` | varchar(300) | Yes | Public | Company website. Nullable. |
| `description` | text | Yes | Public | Company description (unbounded — justified by content nature). Nullable. |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete |

---

### `organisation_identifier`
*Tax IDs, registration numbers, GST etc. Multiple per organisation.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `identifier_type` | varchar(60) | No | Sensitive | Type code (e.g. `'GST'`, `'CIN'`, `'PAN'`) |
| `value` | varchar(200) | No | Sensitive | The identifier value. ⚠️ Should be encrypted at app layer in v1.1. |
| `country_id` | bigint | No | Internal | FK → country (jurisdiction) |
| `verified_at` | timestamptz | Yes | Internal | When the identifier was verified. Nullable = unverified. |

---

### `recruiter`
*Links an app_user to an organisation as a recruiter.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `is_account_admin` | boolean | No | Internal | Whether this recruiter is the account admin |
| `deleted_at` | timestamptz | Yes | Internal | Soft delete (deactivation) |

---

## Module 6: Gig Marketplace

### `gig_request`
*A short-duration project request posted by an organisation.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `city_id` | bigint | Yes | Public | FK → city. Nullable for remote gigs. |
| `gig_status_id` | bigint | No | Public | FK → gig_status (open/assigned/completed/cancelled) |
| `title` | varchar(300) | No | Public | Gig title |
| `description` | text | Yes | Public | Detailed requirements (unbounded). Nullable. |
| `starts_at` | timestamptz | No | Public | Work window start |
| `ends_at` | timestamptz | No | Public | Work window end |
| `pay_amount` | numeric(14,2) | No | Public | Fixed pay for the gig |
| `pay_currency_id` | bigint | No | Public | FK → currency |
| `openings` | integer | No | Public | Number of workers needed |

---

### `gig_worker_profile`
*Gig worker's freelance profile. Separate from candidate_profile.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user (shared identity) |
| `headline` | varchar(300) | Yes | Personal | Gig worker's headline. Nullable. |
| `hourly_rate` | numeric(14,2) | Yes | Internal | Charge rate. Nullable if not set. |
| `rate_currency_id` | bigint | Yes | Internal | FK → currency. Nullable if rate not set. |
| `rating_average` | numeric(3,2) | Yes | Public | Average rating (1.00–5.00). Nullable until first rating. |
| `is_available` | boolean | No | Public | Whether taking new gigs |

---

### `gig_application`
*A gig worker's application (bid) to a gig request.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `gig_request_id` | bigint | No | Internal | FK → gig_request |
| `gig_worker_profile_id` | bigint | No | Internal | FK → gig_worker_profile |
| `gig_application_status_id` | bigint | No | Internal | FK → gig_application_status (applied/accepted/declined/withdrawn) |
| `applied_at` | timestamptz | No | Internal | When the bid was submitted |

---

### `gig_assignment`
*An accepted gig application. EXCLUDE constraint prevents overlapping work windows for the same worker.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `gig_application_id` | bigint | No | Internal | FK → gig_application (unique: one assignment per application) |
| `gig_request_id` | bigint | No | Internal | FK → gig_request |
| `gig_worker_profile_id` | bigint | No | Internal | FK → gig_worker_profile |
| `work_window` | tstzrange | No | Internal | Actual assigned work window (PostgreSQL range type) |
| `fulfilment_reference` | varchar(100) | Yes | Internal | Handoff reference from external fulfilment system. Nullable until handoff. |
| `is_cancelled` | boolean | No | Internal | Whether the assignment was cancelled (excluded from EXCLUDE constraint) |

---

### `gig_rating`
*Rating left by the requester organisation after a completed gig.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `gig_assignment_id` | bigint | No | Internal | FK → gig_assignment |
| `rated_by_app_user_id` | bigint | No | Internal | FK → app_user (who left the rating) |
| `rating` | smallint | No | Public | Score 1–5 |
| `comment` | varchar(1000) | Yes | Public | Optional written review. Nullable. |

---

### `gig_earning_reference`
*Earnings data received from the external fulfilment system. Source of truth is external.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `gig_assignment_id` | bigint | No | Internal | FK → gig_assignment |
| `external_reference` | varchar(100) | No | Internal | Unique reference from fulfilment system (idempotency key) |
| `amount` | numeric(14,2) | No | Internal | Earnings amount |
| `currency_id` | bigint | No | Internal | FK → currency |
| `reconciled_at` | timestamptz | Yes | Internal | When reconciled. Nullable = pending reconciliation. |

---

### `gig_worker_favourite`
*Organisations bookmark gig workers they trust.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation (the one adding the favourite) |
| `gig_worker_profile_id` | bigint | No | Internal | FK → gig_worker_profile |

---

### `gig_worker_blacklist`
*Organisations block gig workers from applying to their requests.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `gig_worker_profile_id` | bigint | No | Internal | FK → gig_worker_profile |
| `reason` | varchar(500) | Yes | Internal | Brief reason for blacklisting. Nullable. |

---

## Module 7: Subscriptions and Payments

### `plan`
*Subscription plan definition.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `code` | varchar(60) | No | Public | Plan code (e.g. `'starter'`, `'pro'`, `'enterprise'`) |
| `name` | varchar(200) | No | Public | Display name |
| `price` | numeric(14,2) | No | Public | Plan price |
| `currency_id` | bigint | No | Public | FK → currency |
| `billing_period_months` | smallint | No | Public | Billing cycle in months (1, 12) |
| `download_credits` | integer | No | Internal | Profile download credits included |
| `max_seats` | integer | No | Internal | Maximum users per licence |

---

### `subscription`
*Organisation's active subscription to a plan. EXCLUDE constraint prevents overlapping periods.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `plan_id` | bigint | No | Internal | FK → plan |
| `subscription_status_id` | bigint | No | Internal | FK → subscription_status (active/expired/cancelled) |
| `period_start` | timestamptz | No | Internal | Subscription period start |
| `period_end` | timestamptz | No | Internal | Subscription period end. CHECK period_end > period_start. |

---

### `payment_order`
*A payment request associated with a subscription.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `subscription_id` | bigint | Yes | Internal | FK → subscription. Nullable for wallet top-ups. |
| `payment_status_id` | bigint | No | Internal | FK → payment_status |
| `amount` | numeric(14,2) | No | Internal | Payment amount |
| `currency_id` | bigint | No | Internal | FK → currency |
| `gateway_reference` | varchar(100) | Yes | Sensitive | Token from payment gateway. NOT card/bank data. Nullable until paid. |
| `idempotency_key` | varchar(100) | No | Internal | Prevents double-charging. UNIQUE. |
| `paid_at` | timestamptz | Yes | Internal | When payment was confirmed. Nullable until paid. |

---

### `wallet`
*Credit balance per organisation. CHECK prevents negative balance.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation. UNIQUE (one wallet per org). |
| `balance_credits` | integer | No | Internal | Current credit balance. CHECK >= 0. |

---

### `wallet_ledger`
*Immutable transaction history. Append-only. Every debit/credit is a new row.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `wallet_id` | bigint | No | Internal | FK → wallet |
| `ledger_entry_type_id` | bigint | No | Internal | FK → ledger_entry_type (purchase/download/refund/adjustment) |
| `credits` | integer | No | Internal | Credit change (negative = debit, positive = credit). CHECK credits <> 0. |
| `balance_after` | integer | No | Internal | Wallet balance after this entry (set by trigger) |
| `payment_order_id` | bigint | Yes | Internal | FK → payment_order. Nullable for non-payment entries. |
| `idempotency_key` | varchar(100) | No | Internal | Prevents duplicate entries. UNIQUE. |
| `occurred_at` | timestamptz | No | Internal | Entry timestamp |

---

### `profile_download`
*Immutable record of every candidate profile download. Append-only.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `organisation_id` | bigint | No | Internal | FK → organisation |
| `recruiter_id` | bigint | No | Internal | FK → recruiter (who downloaded) |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile (who was downloaded) |
| `wallet_ledger_id` | bigint | No | Internal | FK → wallet_ledger (the debit entry). UNIQUE — one ledger entry per download. |
| `downloaded_at` | timestamptz | No | Internal | Download timestamp |

---

## Module 8: Notifications

### `notification`
*Delivered notifications. Partitioned by month (partition name: `notification_p<yyyymm>`).*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK (composite with created_at for partitioning) |
| `app_user_id` | bigint | No | Internal | FK → app_user (recipient) |
| `event_code` | varchar(60) | No | Internal | Event type (e.g. `'application_update'`, `'job_alert'`) |
| `payload` | jsonb | Yes | Internal | Event metadata (IDs, status codes). NOT message body. Nullable. |
| `delivery_status` | varchar(20) | No | Internal | `pending`, `sent`, `failed` |
| `sent_at` | timestamptz | Yes | Internal | When sent. Nullable until delivered. |
| `created_at` | timestamptz | No | Internal | Partition key. UTC. |

---

### `job_alert_preference`
*Candidate's saved job search preferences for alerts.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK |
| `app_user_id` | bigint | No | Internal | FK → app_user |
| `job_role_id` | bigint | Yes | Internal | FK → job_role. Nullable if alert is for any role. |
| `city_id` | bigint | Yes | Internal | FK → city. Nullable if alert is for any location. |
| `salary_min` | numeric(14,2) | Yes | Internal | Minimum salary threshold. Nullable. |
| `alert_frequency_id` | bigint | No | Internal | FK → alert_frequency (daily/weekly/instant) |
| `is_active` | boolean | No | Internal | Whether alerts are enabled |

---

## Module 9: Analytics (dw schema)

### `dw.dim_candidate`
*Slowly-changing dimension for candidates. Used in fact table joins.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | Surrogate PK (DW key) |
| `candidate_profile_id` | bigint | No | Internal | FK → candidate_profile (natural key). UNIQUE. |
| `city_name` | varchar(150) | Yes | Internal | Denormalised city name at time of snapshot. |
| `experience_band` | varchar(20) | No | Internal | `'0-1'`, `'1-3'`, `'3-6'`, `'6+'` |

---

### `dw.dim_job`
*SCD2 dimension for jobs. Tracks title/status changes over time.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | DW surrogate PK |
| `job_id` | bigint | No | Internal | Natural key → job.id |
| `title` | varchar(300) | No | Public | Job title at this version |
| `job_status_code` | varchar(60) | Yes | Internal | Status at this version |
| `role_name` | varchar(200) | Yes | Public | Role name at this version |
| `city_name` | varchar(150) | Yes | Public | City at this version |
| `valid_from` | timestamptz | No | Internal | When this version became current |
| `valid_to` | timestamptz | No | Internal | When this version was superseded (`'infinity'` if current) |
| `is_current` | boolean | No | Internal | True = this is the active version |

---

### `dw.fact_application`
*Application fact table. Loaded from the operational `application` table.*

| Column | Type | Nullable | Sensitivity | Description |
|---|---|---|---|---|
| `id` | bigint | No | Internal | DW surrogate PK |
| `application_id` | bigint | No | Internal | Natural key → application.id. UNIQUE. |
| `dim_job_id` | bigint | No | Internal | FK → dw.dim_job |
| `dim_organisation_id` | bigint | No | Internal | FK → dw.dim_organisation |
| `dim_candidate_id` | bigint | No | Internal | FK → dw.dim_candidate |
| `dim_date_id` | integer | No | Internal | FK → dw.dim_date (YYYYMMDD integer key) |
| `stage_code` | varchar(60) | No | Internal | Current pipeline stage code |
| `is_terminal` | boolean | No | Internal | Whether this is a terminal stage |
| `loaded_at` | timestamptz | No | Internal | When this row was last refreshed |

---

### `dw.mv_daily_application_funnel`
*Materialised view: daily application count by stage. Refreshed by `dw.sp_refresh_dw()`.*

| Column | Type | Sensitivity | Description |
|---|---|---|---|
| `full_date` | date | Public | Calendar date |
| `stage_code` | varchar(60) | Internal | Pipeline stage |
| `application_count` | bigint | Internal | Applications in that stage on that date |

---

*Last updated: October 2026 | Based on schema version with 06b_schema_fixes.sql applied.*
