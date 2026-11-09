import os
import unittest
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException

from app.database import DATABASE_URL, get_connection
from app.development import (
    DEVELOPMENT_HOST_USER_ID,
    DEVELOPMENT_PARTICIPANT_USER_ID,
)
from app.routers.settlements import get_host_settlements


def configured_test_user_ids():
    raw_ids = os.getenv("DORMN_TEST_PARTICIPANT_USER_IDS", "")
    try:
        return tuple(UUID(value.strip()) for value in raw_ids.split(",") if value.strip())
    except ValueError:
        return ()


TEST_PARTICIPANT_USER_IDS = configured_test_user_ids()


@unittest.skipUnless(
    DATABASE_URL
    and os.getenv("RUN_SUPABASE_INTEGRATION") == "1"
    and len(TEST_PARTICIPANT_USER_IDS) >= 3,
    "Set RUN_SUPABASE_INTEGRATION=1 and three pre-seeded public.users UUIDs",
)
class HostSettlementSupabaseIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.post_ids = []
        self.token = uuid4().hex[:8]

    def insert_post(self, cursor, author_id, status, shortfall_policy="KEEP_BY_HOST"):
        cursor.execute(
            """
            INSERT INTO posts (
                author_id,
                product_name,
                total_price,
                total_quantity,
                host_quantity,
                deadline,
                pickup_location,
                shortfall_policy,
                status
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
            """,
            (
                author_id,
                f"integration-{self.token}",
                22900,
                24,
                4,
                datetime.now(timezone.utc) + timedelta(days=1),
                "integration-test",
                shortfall_policy,
                status,
            ),
        )
        post_id = cursor.fetchone()[0]
        self.post_ids.append(post_id)
        return post_id

    def test_host_settlement_states_against_supabase(self):
        with get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    "SELECT id FROM users WHERE id IN (%s, %s)",
                    (DEVELOPMENT_HOST_USER_ID, DEVELOPMENT_PARTICIPANT_USER_ID),
                )
                self.assertEqual(
                    {row[0] for row in cursor.fetchall()},
                    {DEVELOPMENT_HOST_USER_ID, DEVELOPMENT_PARTICIPANT_USER_ID},
                )

                recruiting_post_id = self.insert_post(
                    cursor,
                    DEVELOPMENT_HOST_USER_ID,
                    "RECRUITING",
                )
                cursor.execute(
                    """
                    INSERT INTO participations (post_id, user_id, quantity)
                    VALUES (%s, %s, 4)
                    """,
                    (recruiting_post_id, DEVELOPMENT_PARTICIPANT_USER_ID),
                )

                closed_post_id = self.insert_post(
                    cursor,
                    DEVELOPMENT_HOST_USER_ID,
                    "CLOSED",
                )
                closed_user_ids = TEST_PARTICIPANT_USER_IDS[:3]
                settlement_data = [
                    (closed_user_ids[0], 4, 3816, "UNPAID"),
                    (closed_user_ids[1], 6, 5725, "SENT"),
                    (closed_user_ids[2], 2, 1908, "CONFIRMED"),
                ]
                for user_id, quantity, amount, payment_status in settlement_data:
                    cursor.execute(
                        """
                        INSERT INTO participations (post_id, user_id, quantity)
                        VALUES (%s, %s, %s)
                        RETURNING id
                        """,
                        (closed_post_id, user_id, quantity),
                    )
                    participation_id = cursor.fetchone()[0]
                    cursor.execute(
                        """
                        INSERT INTO settlements (
                            participation_id,
                            amount,
                            payment_status,
                            sent_at,
                            confirmed_at
                        )
                        VALUES (
                            %s,
                            %s,
                            %s,
                            CASE WHEN %s IN ('SENT', 'CONFIRMED') THEN NOW() END,
                            CASE WHEN %s = 'CONFIRMED' THEN NOW() END
                        )
                        """,
                        (
                            participation_id,
                            amount,
                            payment_status,
                            payment_status,
                            payment_status,
                        ),
                    )

                cancelled_post_id = self.insert_post(
                    cursor,
                    DEVELOPMENT_HOST_USER_ID,
                    "CANCELLED",
                    "CANCEL_IF_SHORT",
                )
                cursor.execute(
                    """
                    INSERT INTO participations (post_id, user_id, quantity)
                    VALUES (%s, %s, 4)
                    """,
                    (cancelled_post_id, DEVELOPMENT_PARTICIPANT_USER_ID),
                )

                forbidden_post_id = self.insert_post(
                    cursor,
                    DEVELOPMENT_PARTICIPANT_USER_ID,
                    "RECRUITING",
                )

        recruiting = get_host_settlements(
            recruiting_post_id,
            DEVELOPMENT_HOST_USER_ID,
        )
        self.assertEqual(recruiting["participants"][0]["amount"], 3816)
        self.assertIsNone(recruiting["participants"][0]["settlement_id"])
        self.assertIsNone(recruiting["participants"][0]["payment_status"])
        self.assertEqual(recruiting["participant_total_amount"], 3816)
        self.assertEqual(recruiting["host_amount"], 19084)

        with get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT COUNT(*)
                    FROM settlements AS s
                    JOIN participations AS p ON p.id = s.participation_id
                    WHERE p.post_id = %s
                    """,
                    (recruiting_post_id,),
                )
                self.assertEqual(cursor.fetchone()[0], 0)

        closed = get_host_settlements(closed_post_id, DEVELOPMENT_HOST_USER_ID)
        self.assertEqual(
            [participant["payment_status"] for participant in closed["participants"]],
            ["UNPAID", "SENT", "CONFIRMED"],
        )
        self.assertEqual(closed["participant_total_amount"], 11449)
        self.assertEqual(closed["host_amount"], 11451)

        cancelled = get_host_settlements(cancelled_post_id, DEVELOPMENT_HOST_USER_ID)
        self.assertIsNone(cancelled["participants"][0]["amount"])
        self.assertIsNone(cancelled["participants"][0]["payment_status"])
        self.assertEqual(cancelled["participant_total_amount"], 0)
        self.assertEqual(cancelled["host_amount"], 0)

        with self.assertRaises(HTTPException) as forbidden_context:
            get_host_settlements(
                forbidden_post_id,
                DEVELOPMENT_PARTICIPANT_USER_ID,
            )
        self.assertEqual(forbidden_context.exception.status_code, 403)

        with self.assertRaises(HTTPException) as missing_context:
            get_host_settlements(9999999999, DEVELOPMENT_HOST_USER_ID)
        self.assertEqual(missing_context.exception.status_code, 404)

    def tearDown(self):
        with get_connection() as conn:
            with conn.cursor() as cursor:
                for post_id in self.post_ids:
                    cursor.execute("DELETE FROM posts WHERE id = %s", (post_id,))


if __name__ == "__main__":
    unittest.main()
