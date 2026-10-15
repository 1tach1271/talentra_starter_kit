# Task board, Day 1 (tick when the deliverable file exists)

## Shashi (Member A)
- [ ] Create GitHub repo, add Kudrat and Kshitij, protect main (require 1 review)
- [ ] Push this starter kit
- [ ] B1 to B3: sign decision files
- [ ] Draft Jobs and Applications entities (B6), then validate Profile (B5)
- [ ] Phase 2: Administration (B24, B27, B30, B33), file schema/020_administration.sql
- [ ] Phase 3: Licences, devices, sessions (B36, B39, B42, B45), file schema/070_licence_session.sql
- [ ] Shared items: credentials, consent, audit, blocking (B50, B53, B56, B59)

## Kudrat (Member B)
- [ ] Run docker compose, confirm connection, run 000 and 010 SQL
- [ ] Download master data sources, load with COPY (seed/load_master_data.py)
- [ ] Draft Profile columns with Kshitij (B12), validate Jobs entities (B7)
- [ ] Phase 2: Organisation and account (B25, B28, B31, B34), schema/030_organisation.sql
- [ ] Phase 3: Sourcing and consultant requests (B37, B40, B43, B46), schema/080_sourcing.sql
- [ ] Analytics star schema (B49, B52, B55, B58), schema/110_analytics.sql

## Kshitij (Member C)
- [ ] Create docs: data_dictionary.xlsx, compliance table, integration boundary table, competitor comparison
- [ ] Draft Profile entities (B4), validate Jobs entities (B7)
- [ ] Gig decision write-up (D4)
- [ ] Phase 2: Gig marketplace (B26, B29, B32, B35), schema/040_gig.sql
- [ ] Phase 3: Subscriptions, wallet, payments, downloads (B38, B41, B44, B47), schema/090_billing.sql
- [ ] Notifications, preferences, community (B48, B51, B54, B57), schema/100_notification.sql

## Schema file order
000_setup, 010_master_data, 015_profile, 018_job_application, 020_administration, 030_organisation,
040_gig, 070_licence_session, 080_sourcing, 090_billing, 100_notification, 110_analytics, 900_audit_fks
