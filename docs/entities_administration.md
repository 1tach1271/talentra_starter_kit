# Administration: Entity List (B24)

**Author:** Shashi

| # | Entity | Purpose | Delete policy |
|---|---|---|---|
| 1 | `app_user` | Every account (candidate, employer, recruiter, consultant, admin, TPO). Stores email, status, and user type. | Soft |
| 2 | `app_role` | Role definitions: super_admin, admin, account_admin, guest, candidate, employer, recruiter, consultant, placement_officer. | Deactivate |
| 3 | `permission` | Atomic actions, such as `job.publish` and `profile.download`. | Deactivate |
| 4 | `app_role_permission` | Maps roles to permissions. | Hard |
| 5 | `app_user_role` | User-to-role assignment with effective dates. | Soft (end date) |
| 6 | `credential` | Password hash and authentication method per user. Sensitive data. | Hard on account deletion |
| 7 | `consent_record` | Consent given or withdrawn per user, purpose, and version. | Append-only |
| 8 | `identity_session` | Login identity token; device-limited sessions belong to the Licence module. | Hard after expiry |
| 9 | `audit_event` | Append-only record of sensitive actions. | Append-only |
| 10 | `error_log` | System errors for troubleshooting. | Append-only |
| 11 | `block_entry` | Records blocking relationships between candidates, employers, recruiters, consultants, and companies. | Soft (unblock) |
