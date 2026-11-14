import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.posts import get_post, get_posts


AUTHOR_ID = UUID("11111111-1111-1111-1111-111111111111")


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params=None):
        self.calls.append((query, params))

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def post_row():
    return {
        "id": 10,
        "author_id": AUTHOR_ID,
        "product_name": "햇반 24개",
        "product_url": None,
        "image_url": None,
        "total_price": 22900,
        "total_quantity": 24,
        "host_quantity": 4,
        "deadline": datetime(2026, 11, 20, tzinfo=timezone.utc),
        "pickup_location": "기숙사 로비",
        "shortfall_policy": "KEEP_BY_HOST",
        "status": "RECRUITING",
        "created_at": datetime(2026, 11, 15, tzinfo=timezone.utc),
        "author_room_number": "717-1",
        "joined_quantity": 10,
        "remaining_quantity": 10,
        "participant_count": 2,
    }


class PostRecruitmentResponseTest(unittest.TestCase):
    def test_post_list_includes_recruitment_summary(self):
        connection = FakeConnection([post_row()])

        with patch("app.routers.posts.get_connection", return_value=connection):
            post = get_posts()["data"][0]

        self.assertEqual(post.author_room_number, "717-1")
        self.assertEqual(post.joined_quantity, 10)
        self.assertEqual(post.remaining_quantity, 10)
        self.assertEqual(post.participant_count, 2)

    def test_post_detail_includes_recruitment_summary(self):
        connection = FakeConnection([post_row()])

        with patch("app.routers.posts.get_connection", return_value=connection):
            post = get_post(10)["data"]

        self.assertEqual(post.remaining_quantity, 10)
        self.assertEqual(connection.cursor_instance.calls[0][1], (10,))

    def test_missing_post_returns_not_found(self):
        connection = FakeConnection([])

        with patch("app.routers.posts.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                get_post(999)

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "POST_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
