# Decision log
| ID | Date | Decision | Reason | Trade-off / risk | Owner |
|---|---|---|---|---|---|
| D1 | 15 Oct | PostgreSQL 16 | See B1 | Team must learn RLS and gist | All |
| D2 | 15 Oct | bigint identity PKs | Compact, fast at 100M rows | Not globally unique; public_id uuid where exposed | All |
| D3 | 15 Oct | Lookup tables for enums | Docket rule group 3 | Extra joins | All |
| D4 | TBD | Gig model: separate subsystem sharing app_user and organisation (proposed) | Different rules: one-way bids, windows, external fulfilment | Cross-type reporting needs a union view / dw fact | Kshitij to write |
| D5 | 15 Oct | Tier 3 domains not in v1 | Time | Lower coverage score | All |
| D6 | 15 Oct | Sub-roles in employer org out of scope | Docket | Extension: organisation_member_role table later | Shashi |
