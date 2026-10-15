# Jobs and Applications: Entity List (B6)

**Author:** Shashi  
**Reviewers:** Kudrat, Kshitij

| # | Entity | Purpose | Delete policy |
|---|---|---|---|
| 1 | `job_requirement` | A posted demand: title, category, organisation, status, publish state, open-to-consultants flag, salary range, description | Soft |
| 2 | `job_position` | Individual openings under one requirement (count, location, status) | Soft |
| 3 | `job_requirement_skill` | Skills needed for a requirement (mandatory or preferred) | Hard (owned child) |
| 4 | `job_requirement_location` | Cities where the job can be done | Hard (owned child) |
| 5 | `job_requirement_status_history` | Every status/publish change of a requirement | Append-only |
| 6 | `questionnaire` | Question set attached to a requirement | Soft |
| 7 | `question` | One question (type, text, required flag) | Soft |
| 8 | `question_option` | Choices for choice-type questions | Hard (owned child) |
| 9 | `application` | A candidate applying to a requirement (one per candidate per requirement) | Soft |
| 10 | `application_answer` | Candidate's answer to a question | Hard (owned child) |
| 11 | `application_status_history` | Every status move (applied, shortlisted, interviewed, offered, joined, rejected), with actor and reason | Append-only |
| 12 | `shortlist` | A named shortlist owned by a recruiter/employer for a requirement | Soft |
| 13 | `shortlist_entry` | A candidate or application inside a shortlist | Hard |
| 14 | `interview` | Scheduled interview for an application (time, mode, outcome) | Soft |
| 15 | `offer` | Offer made on an application (salary, joining date, accepted/declined) | Soft |
| 16 | `job_search_history` | Candidate's searches (filters and timestamp) | Append-only, 12-month retention |

## Design notes to validate

- Gigs are not included in these tables; they belong to a separate gig subsystem (decision D4). `job_category` excludes gigs for this module.
- "Joined" and "rejected" are statuses in `application_status_history`, with a rejection-reason reference code; no separate table is proposed.
- `application` has a `current_status_id` for fast reads; history remains the source of truth.
- Candidate application history (Section 4, Tier 2) is queried from `application`; no extra table is proposed.
- The Sourcing module references `shortlist_entry`.
- `application` and `job_search_history` are partitioning candidates at full scale (100 million rows).

## Open questions for review

1. Should one candidate have one application per requirement, with reapplication allowed after withdrawal?
2. Can one requirement have several questionnaires, or exactly one?
3. Is `job_position` necessary as a separate table, or is a `positions_count` column sufficient?
