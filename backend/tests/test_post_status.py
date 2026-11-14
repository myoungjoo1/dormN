import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.posts import update_post_status
from app.schemas.posts import PostStatusUpdateRequest


HOST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
OTHER_USER_ID = UUID("22222222-2222-2222-2222-222222222222")


class FakeCursor:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def post_row(status="CLOSED", author_id=HOST_USER_ID):
    return {
        "id": 10,
        "author_id": author_id,
        "product_name": "햇반 24개",
        "product_url": None,
        "image_url": None,
        "total_price": 22900,
        "total_quantity": 24,
        "host_quantity": 4,
        "deadline": datetime(2026, 11, 20, tzinfo=timezone.utc),
        "pickup_location": "기숙사 로비",
        "shortfall_policy": "KEEP_BY_HOST",
        "status": status,
        "created_at": datetime(2026, 11, 15, tzinfo=timezone.utc),
    }


class PostStatusUpdateTest(unittest.TestCase):
    def call_endpoint(self, rows, target_status, user_id=HOST_USER_ID):
        connection = FakeConnection(rows)
        with patch("app.routers.posts.get_connection", return_value=connection):
            result = update_post_status(
                10,
                PostStatusUpdateRequest(status=target_status),
                user_id,
            )
        return result["data"], connection

    def test_closed_post_can_be_ordered_after_all_settlements_confirmed(self):
        updated_post, connection = self.call_endpoint(
            [
                post_row("CLOSED"),
                {"pending_count": 0},
                post_row("ORDERED"),
            ],
            "ORDERED",
        )

        self.assertEqual(updated_post.status, "ORDERED")
        self.assertEqual(connection.cursor_instance.calls[-1][1], ("ORDERED", 10))

    def test_closed_post_cannot_be_ordered_with_pending_settlements(self):
        with self.assertRaises(HTTPException) as context:
            self.call_endpoint(
                [post_row("CLOSED"), {"pending_count": 1}],
                "ORDERED",
            )

        self.assertEqual(context.exception.code, "SETTLEMENTS_NOT_CONFIRMED")

    def test_each_later_status_moves_one_step(self):
        transitions = (
            ("ORDERED", "ARRIVED"),
            ("ARRIVED", "PICKUP"),
            ("PICKUP", "COMPLETED"),
        )

        for current_status, target_status in transitions:
            with self.subTest(current_status=current_status):
                updated_post, _ = self.call_endpoint(
                    [post_row(current_status), post_row(target_status)],
                    target_status,
                )
                self.assertEqual(updated_post.status, target_status)

    def test_status_cannot_skip_a_step(self):
        with self.assertRaises(HTTPException) as context:
            self.call_endpoint([post_row("CLOSED")], "ARRIVED")

        self.assertEqual(context.exception.code, "INVALID_POST_STATUS_TRANSITION")

    def test_recruiting_cancelled_and_completed_posts_cannot_be_advanced(self):
        for current_status in ("RECRUITING", "CANCELLED", "COMPLETED"):
            with self.subTest(current_status=current_status):
                with self.assertRaises(HTTPException) as context:
                    self.call_endpoint([post_row(current_status)], "ORDERED")
                self.assertEqual(
                    context.exception.code,
                    "INVALID_POST_STATUS_TRANSITION",
                )

    def test_non_author_cannot_change_status(self):
        with self.assertRaises(HTTPException) as context:
            self.call_endpoint(
                [post_row("CLOSED")],
                "ORDERED",
                user_id=OTHER_USER_ID,
            )

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "POST_AUTHOR_REQUIRED")

    def test_missing_post_returns_not_found(self):
        with self.assertRaises(HTTPException) as context:
            self.call_endpoint([], "ORDERED")

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "POST_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
