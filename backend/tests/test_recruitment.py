import os
import unittest
from unittest.mock import call, patch
from uuid import UUID

from app.database import DATABASE_URL, get_connection
from app.services.recruitment import (
    finalize_recruitment,
    process_expired_recruitment_once,
)


class FakeCursor:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params=None):
        self.calls.append((query, params))

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None

    def fetchall(self):
        return self.rows.pop(0) if self.rows else []


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def post_row(
    *,
    status="RECRUITING",
    policy="KEEP_BY_HOST",
    deadline_reached=False,
):
    return {
        "id": 10,
        "status": status,
        "total_price": 22900,
        "total_quantity": 24,
        "host_quantity": 4,
        "shortfall_policy": policy,
        "deadline_reached": deadline_reached,
    }


def finalized_post(status, host_quantity):
    return {
        "id": 10,
        "status": status,
        "host_quantity": host_quantity,
    }


class RecruitmentFinalizationTest(unittest.TestCase):
    def call_finalize(self, rows):
        connection = FakeConnection(rows)
        with patch("app.services.recruitment.create_settlements") as create:
            result = finalize_recruitment(connection, 10)
        return result, connection, create

    def test_recruiting_post_stays_open_before_deadline_when_not_full(self):
        result, connection, create = self.call_finalize(
            [post_row(), {"participant_quantity": 10}]
        )

        self.assertIsNone(result)
        self.assertEqual(len(connection.cursor_instance.calls), 2)
        create.assert_not_called()

    def test_keep_by_host_closes_and_takes_remaining_quantity_at_deadline(self):
        result, connection, create = self.call_finalize(
            [
                post_row(deadline_reached=True),
                {"participant_quantity": 10},
                finalized_post("CLOSED", 14),
            ]
        )

        self.assertEqual(result["status"], "CLOSED")
        self.assertEqual(
            connection.cursor_instance.calls[2][1],
            (14, "CLOSED", 10),
        )
        create.assert_called_once_with(connection, 10, 22900, 24)

    def test_cancel_if_short_cancels_without_settlements_at_deadline(self):
        result, connection, create = self.call_finalize(
            [
                post_row(
                    policy="CANCEL_IF_SHORT",
                    deadline_reached=True,
                ),
                {"participant_quantity": 10},
                finalized_post("CANCELLED", 4),
            ]
        )

        self.assertEqual(result["status"], "CANCELLED")
        self.assertEqual(
            connection.cursor_instance.calls[2][1],
            (4, "CANCELLED", 10),
        )
        create.assert_not_called()

    def test_full_post_closes_before_deadline_and_creates_settlements(self):
        result, _, create = self.call_finalize(
            [
                post_row(policy="CANCEL_IF_SHORT"),
                {"participant_quantity": 20},
                finalized_post("CLOSED", 4),
            ]
        )

        self.assertEqual(result["status"], "CLOSED")
        create.assert_called_once()

    def test_already_finalized_post_is_ignored(self):
        result, connection, create = self.call_finalize([post_row(status="CLOSED")])

        self.assertIsNone(result)
        self.assertEqual(len(connection.cursor_instance.calls), 1)
        create.assert_not_called()

    def test_scheduler_processes_each_expired_recruitment(self):
        connection = FakeConnection([[(10,), (11,)]])

        with patch(
            "app.services.recruitment.get_connection",
            return_value=connection,
        ), patch("app.services.recruitment.finalize_recruitment") as finalize:
            process_expired_recruitment_once()

        self.assertEqual(
            finalize.call_args_list,
            [call(connection, 10), call(connection, 11)],
        )


@unittest.skipUnless(
    DATABASE_URL and os.getenv("RUN_SUPABASE_INTEGRATION") == "1",
    "Set RUN_SUPABASE_INTEGRATION=1 to run PostgreSQL integration tests",
)
class RecruitmentPostgresIntegrationTest(unittest.TestCase):
    def test_deadline_policies_create_only_valid_settlements(self):
        author_id = UUID("11111111-1111-1111-1111-111111111111")
        participant_id = UUID("22222222-2222-2222-2222-222222222222")

        with get_connection() as connection:
            with connection.cursor() as cursor:
                for table in ("posts", "participations", "settlements"):
                    cursor.execute(
                        f"""
                        CREATE TEMP TABLE {table}
                        (LIKE public.{table} INCLUDING ALL)
                        ON COMMIT DROP
                        """
                    )

                for post_id, policy in (
                    (101, "KEEP_BY_HOST"),
                    (102, "CANCEL_IF_SHORT"),
                ):
                    cursor.execute(
                        """
                        INSERT INTO posts (
                            id,
                            author_id,
                            product_name,
                            total_price,
                            total_quantity,
                            host_quantity,
                            deadline,
                            pickup_location,
                            shortfall_policy
                        )
                        VALUES (
                            %s, %s, 'integration-test', 22900, 24, 4,
                            NOW() - INTERVAL '1 minute',
                            'integration-test', %s
                        )
                        """,
                        (post_id, author_id, policy),
                    )
                    cursor.execute(
                        """
                        INSERT INTO participations (
                            id, post_id, user_id, quantity
                        )
                        VALUES (%s, %s, %s, 10)
                        """,
                        (post_id, post_id, participant_id),
                    )

            finalize_recruitment(connection, 101)
            finalize_recruitment(connection, 102)

            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT id, status, host_quantity
                    FROM posts
                    ORDER BY id
                    """
                )
                self.assertEqual(
                    cursor.fetchall(),
                    [(101, "CLOSED", 14), (102, "CANCELLED", 4)],
                )

                cursor.execute(
                    """
                    SELECT p.post_id, s.amount, s.payment_status
                    FROM settlements AS s
                    JOIN participations AS p ON p.id = s.participation_id
                    ORDER BY p.post_id
                    """
                )
                self.assertEqual(cursor.fetchall(), [(101, 9541, "UNPAID")])


if __name__ == "__main__":
    unittest.main()
