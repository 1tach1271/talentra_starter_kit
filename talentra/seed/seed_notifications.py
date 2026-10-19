"""
seed/seed_notifications.py
Seeds:
  notification_preference, privacy_setting,
  job_alert_preference, notification,
  community_post, community_comment,
  support_ticket, support_ticket_message,
  faq
"""

import random
from datetime import datetime, timedelta, timezone

import psycopg
from faker import Faker

from config import DSN, N_NOTIFICATIONS, BATCH_SIZE

fake = Faker("en_IN")
random.seed(42)
Faker.seed(42)

NOW = datetime.now(timezone.utc)

EVENT_CODES = [
    "job_match",
    "application_update",
    "profile_view",
    "shortlisted",
    "interview_scheduled",
    "offer_received",
    "alert_digest",
    "gig_request_match",
    "payment_received",
    "system_announcement",
]

COMMUNITY_TOPICS = [
    "Resume Tips for Freshers",
    "How I Cracked My First Tech Interview",
    "Top 5 Skills Employers Look for in 2026",
    "Salary Negotiation – Do's and Don'ts",
    "Remote Work: My Experience After 2 Years",
    "Best Free Certifications for Data Science",
    "How to Write a Standout Cover Letter",
    "LinkedIn vs Talentra – What Works?",
    "Switching Careers at 30 – My Journey",
    "Interview Questions You Must Prepare For",
    "Working as a Gig Worker – Honest Review",
    "How Recruiters Actually Filter Resumes",
]

FAQS = [
    ("How do I reset my password?",
     "Click 'Forgot Password' on the login page and follow the instructions sent to your email."),
    ("How do I upload my resume?",
     "Go to your profile page, click 'Resume', then 'Upload'. Supported formats: PDF, DOCX."),
    ("Can I apply to multiple jobs at once?",
     "Yes. You can apply to as many jobs as you like from the Jobs section."),
    ("How do I track my application status?",
     "Visit My Applications in your dashboard. Each application shows its current pipeline stage."),
    ("How does the credit system work?",
     "Employers purchase credits to download candidate profiles and send bulk outreach."),
    ("What is a gig request?",
     "A gig request is a short-duration work opportunity with a fixed start/end time and pay rate."),
    ("How do I block a recruiter?",
     "Go to the recruiter's profile and click 'Block'. They will no longer be able to view your profile."),
    ("How do I delete my account?",
     "Contact support@talentra.com with your registered email and we will process your deletion request."),
]


def _id_map(cur, table, key_col="code"):
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {r[0]: r[1] for r in cur.fetchall()}


def run(conn):
    with conn.cursor() as cur:

        # --- reference data ---
        all_user_ids      = [r[0] for r in cur.execute("SELECT id FROM app_user ORDER BY id").fetchall()]
        profile_ids       = [r[0] for r in cur.execute("SELECT id FROM candidate_profile ORDER BY id").fetchall()]
        candidate_user_ids= [r[0] for r in cur.execute(
            "SELECT app_user_id FROM candidate_profile ORDER BY id"
        ).fetchall()]

        channel_ids  = list(_id_map(cur, "notification_channel").values())
        noti_stat_ids= list(_id_map(cur, "notification_status").values())
        lang_ids     = list(_id_map(cur, "language").values())
        job_ids      = [r[0] for r in cur.execute("SELECT id FROM job WHERE deleted_at IS NULL ORDER BY id").fetchall()]
        job_role_ids = list(_id_map(cur, "job_role").values())
        city_ids     = [r[0] for r in cur.execute("SELECT id FROM city").fetchall()]
        work_type_ids= list(_id_map(cur, "work_type").values())
        alert_freq_ids= list(_id_map(cur, "alert_frequency").values())
        inr_id       = cur.execute("SELECT id FROM currency WHERE code='INR'").fetchone()[0]
        ticket_stat_ids  = list(_id_map(cur, "ticket_status").values())
        ticket_prio_ids  = list(_id_map(cur, "ticket_priority").values())

        open_ticket_id = cur.execute(
            "SELECT id FROM ticket_status WHERE code='open'"
        ).fetchone()[0]

        # ── 1. privacy_settings (one per candidate user) ──────────────────
        privacy_rows = [
            (uid, random.random() > 0.1, random.random() > 0.7, random.random() > 0.8)
            for uid in candidate_user_ids
        ]
        for batch_start in range(0, len(privacy_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO privacy_setting
                  (app_user_id, is_searchable, show_phone, show_email)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (app_user_id) DO NOTHING
                """,
                privacy_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  privacy_settings:     {cur.rowcount} inserted")

        # ── 2. notification_preferences ───────────────────────────────────
        pref_rows = []
        for uid in candidate_user_ids[:min(len(candidate_user_ids), 100)]:
            for ch_id in random.sample(channel_ids, random.randint(1, len(channel_ids))):
                for event in random.sample(EVENT_CODES, random.randint(2, 4)):
                    pref_rows.append((uid, ch_id, event, random.random() > 0.2))

        for batch_start in range(0, len(pref_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO notification_preference
                  (app_user_id, notification_channel_id, event_code, is_enabled)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (app_user_id, notification_channel_id, event_code) DO NOTHING
                """,
                pref_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  notification_prefs:   {len(pref_rows)} rows")

        # ── 3. job_alert_preferences ──────────────────────────────────────
        existing_alerts = cur.execute("SELECT count(*) FROM job_alert_preference").fetchone()[0]
        if existing_alerts > 0:
            print(f"  job_alert_prefs:      {existing_alerts} already exist, skipping")
        else:
            alert_rows = []
            for pid in profile_ids[:min(len(profile_ids), 100)]:
                uid = cur.execute(
                    "SELECT app_user_id FROM candidate_profile WHERE id=%s", (pid,)
                ).fetchone()[0]
                alert_rows.append((
                    pid,
                    random.choice(job_role_ids),
                    random.choice(city_ids),
                    random.choice(work_type_ids),
                    round(random.randint(3, 15) * 100_000, 2),
                    inr_id,
                    random.choice(alert_freq_ids),
                    True,
                ))

            cur.executemany(
                """
                INSERT INTO job_alert_preference
                  (candidate_profile_id, job_role_id, city_id, work_type_id,
                   min_salary, salary_currency_id, alert_frequency_id, is_active)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                alert_rows,
            )
            print(f"  job_alert_prefs:      {len(alert_rows)} rows")

        # ── 4. notifications ──────────────────────────────────────────────
        # Build and insert in chunks to avoid holding 2M tuples in RAM.
        NOTIF_CHUNK = 50_000
        base_time   = NOW - timedelta(days=90)
        total_inserted = 0
        for chunk_start in range(0, N_NOTIFICATIONS, NOTIF_CHUNK):
            chunk_end  = min(chunk_start + NOTIF_CHUNK, N_NOTIFICATIONS)
            notif_rows = []
            for i in range(chunk_start, chunk_end):
                uid      = random.choice(candidate_user_ids)
                ch_id    = random.choice(channel_ids)
                stat_id  = random.choice(noti_stat_ids)
                event    = random.choice(EVENT_CODES)
                created  = base_time + timedelta(minutes=i * (90 * 24 * 60 // N_NOTIFICATIONS))
                sent_at  = created + timedelta(seconds=random.randint(1, 60)) \
                           if random.random() > 0.1 else None
                notif_rows.append((uid, ch_id, stat_id, event, created, sent_at))

            for batch_start in range(0, len(notif_rows), BATCH_SIZE):
                cur.executemany(
                    """
                    INSERT INTO notification
                      (app_user_id, notification_channel_id, notification_status_id,
                       event_code, created_at, sent_at)
                    VALUES (%s,%s,%s,%s,%s,%s)
                    """,
                    notif_rows[batch_start: batch_start + BATCH_SIZE],
                )
            conn.commit()
            total_inserted += len(notif_rows)
            if chunk_start % 500_000 == 0:
                print(f"  ... notifications {total_inserted}/{N_NOTIFICATIONS}")

        print(f"  notifications:        {total_inserted} inserted")

        # ── 5. community_posts ────────────────────────────────────────────
        existing_posts = cur.execute("SELECT count(*) FROM community_post").fetchone()[0]
        if existing_posts > 0:
            # Rerun — reuse existing post_ids, skip insert
            post_ids = [r[0] for r in cur.execute("SELECT id FROM community_post ORDER BY id").fetchall()]
            print(f"  community_posts:      {existing_posts} already exist, skipping")
        else:
            post_ids = []
            for i, topic in enumerate(COMMUNITY_TOPICS):
                uid = random.choice(candidate_user_ids)
                cur.execute(
                    """
                    INSERT INTO community_post (app_user_id, title, body, is_published)
                    VALUES (%s,%s,%s,%s)
                    RETURNING id
                    """,
                    (uid, topic, fake.paragraph(nb_sentences=5), True),
                )
                post_ids.append(cur.fetchone()[0])
            print(f"  community_posts:      {len(post_ids)} rows")

        # ── 6. community_comments (2-4 per post) ──────────────────────────
        existing_comments = cur.execute("SELECT count(*) FROM community_comment").fetchone()[0]
        if existing_comments > 0:
            print(f"  community_comments:   {existing_comments} already exist, skipping")
        else:
            comment_rows = []
            for pid in post_ids:
                for _ in range(random.randint(2, 4)):
                    uid = random.choice(candidate_user_ids)
                    comment_rows.append((pid, uid, fake.sentence(nb_words=12)))

            cur.executemany(
                """
                INSERT INTO community_comment (community_post_id, app_user_id, body)
                VALUES (%s,%s,%s)
                """,
                comment_rows,
            )
            print(f"  community_comments:   {len(comment_rows)} rows")

        # ── 7. support_tickets (one per 20 candidates) ────────────────────
        existing_tickets = cur.execute("SELECT count(*) FROM support_ticket").fetchone()[0]
        if existing_tickets > 0:
            print(f"  support_tickets:      {existing_tickets} already exist, skipping")
            print(f"  ticket_messages:      (skipped)")
        else:
            ticket_subjects = [
                "Cannot login to my account",
                "Profile not visible to recruiters",
                "Application stuck at Applied stage",
                "Credits deducted but profile not downloaded",
                "Duplicate job posting from same company",
                "Wrong salary shown in job listing",
                "Notification emails not received",
                "Request to delete my account",
                "Resume upload failing",
                "Interview invitation link expired",
            ]
            ticket_ids = []
            sample_users = random.sample(candidate_user_ids, min(len(ticket_subjects), len(candidate_user_ids)))
            for uid, subject in zip(sample_users, ticket_subjects):
                cur.execute(
                    """
                    INSERT INTO support_ticket
                      (app_user_id, ticket_status_id, ticket_priority_id, subject)
                    VALUES (%s,%s,%s,%s)
                    RETURNING id
                    """,
                    (uid, open_ticket_id,
                     random.choice(ticket_prio_ids), subject),
                )
                ticket_ids.append((cur.fetchone()[0], uid))
            print(f"  support_tickets:      {len(ticket_ids)} rows")

            # ── 8. support_ticket_messages (first message from user) ──────────
            ticket_msg_rows = [
                (tid, uid,
                 f"Hi Support, I'm facing an issue: {fake.sentence(nb_words=15)} "
                 f"Please help resolve this at the earliest. Thank you.")
                for tid, uid in ticket_ids
            ]
            cur.executemany(
                """
                INSERT INTO support_ticket_message (support_ticket_id, author_app_user_id, body)
                VALUES (%s,%s,%s)
                """,
                ticket_msg_rows,
            )
            print(f"  ticket_messages:      {len(ticket_msg_rows)} rows")

        # ── 9. FAQs ───────────────────────────────────────────────────────
        existing_faqs = cur.execute("SELECT count(*) FROM faq").fetchone()[0]
        if existing_faqs > 0:
            print(f"  faqs:                 {existing_faqs} already exist, skipping")
        else:
            en_lang_id = cur.execute("SELECT id FROM language WHERE code='en'").fetchone()[0]
            faq_rows = [
                (en_lang_id, q, a, i, True)
                for i, (q, a) in enumerate(FAQS)
            ]
            cur.executemany(
                """
                INSERT INTO faq (language_id, question, answer, display_order, is_published)
                VALUES (%s,%s,%s,%s,%s)
                """,
                faq_rows,
            )
            print(f"  faqs:                 {len(faq_rows)} rows")

    conn.commit()
    print("✓ seed_notifications done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
