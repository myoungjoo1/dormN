import os
import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi import HTTPException

from app.database import DATABASE_URL, get_connection
from app.routers.settlements import get_host_settlements


@unittest.skipUnless(
    DATABASE_URL and os.getenv("RUN_SUPABASE_INTEGRATION") == "1",
    "Set RUN_SUPABASE_INTEGRATION=1 to run against Supabase",
)
class HostSettlementSupabaseIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.post_ids = []
        self.temp_user_ids = []
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

    def insert_temp_user(self, cursor, index):
        cursor.execute(
            """
            INSERT INTO users (kakao_id, room_number)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"integration-{self.token}-{index}", f"it-{self.token}-{index}"),
        )
        user_id = cursor.fetchone()[0]
        self.temp_user_ids.append(user_id)
        return user_id

    def test_host_settlement_states_against_supabase(self):
        with get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT id FROM users WHERE id IN (1, 4) ORDER BY id")
                self.assertEqual([row[0] for row in cursor.fetchall()], [1, 4])

                recruiting_post_id = self.insert_post(cursor, 1, "RECRUITING")
                cursor.execute(
                    """
                    INSERT INTO participations (post_id, user_id, quantity)
                    VALUES (%s, 4, 4)
                    """,
                    (recruiting_post_id,),
                )

                closed_post_id = self.insert_post(cursor, 1, "CLOSED")
                closed_user_ids = [self.insert_temp_user(cursor, index) for index in range(3)]
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
                    1,
                    "CANCELLED",
                    "CANCEL_IF_SHORT",
                )
                cursor.execute(
                    """
                    INSERT INTO participations (post_id, user_id, quantity)
                    VALUES (%s, 4, 4)
                    """,
                    (cancelled_post_id,),
                )

                forbidden_post_id = self.insert_post(cursor, 4, "RECRUITING")

        recruiting = get_host_settlements(recruiting_post_id)
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

        closed = get_host_settlements(closed_post_id)
        self.assertEqual(
            [participant["payment_status"] for participant in closed["participants"]],
            ["UNPAID", "SENT", "CONFIRMED"],
        )
        self.assertEqual(closed["participant_total_amount"], 11449)
        self.assertEqual(closed["host_amount"], 11451)

        cancelled = get_host_settlements(cancelled_post_id)
        self.assertIsNone(cancelled["participants"][0]["amount"])
        self.assertIsNone(cancelled["participants"][0]["payment_status"])
        self.assertEqual(cancelled["participant_total_amount"], 0)
        self.assertEqual(cancelled["host_amount"], 0)

        with self.assertRaises(HTTPException) as forbidden_context:
            get_host_settlements(forbidden_post_id)
        self.assertEqual(forbidden_context.exception.status_code, 403)

        with self.assertRaises(HTTPException) as missing_context:
            get_host_settlements(9999999999)
        self.assertEqual(missing_context.exception.status_code, 404)

    def tearDown(self):
        with get_connection() as conn:
            with conn.cursor() as cursor:
                for post_id in self.post_ids:
                    cursor.execute("DELETE FROM posts WHERE id = %s", (post_id,))
                for user_id in self.temp_user_ids:
                    cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))


if __name__ == "__main__":
    unittest.main()
