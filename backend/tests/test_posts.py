import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.posts import create_post, get_post, get_posts
from app.schemas.posts import PostCreateRequest
from app.services.product_metadata import ProductMetadata


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


def post_row(image_url=None):
    return {
        "id": 10,
        "author_id": AUTHOR_ID,
        "product_name": "햇반 24개",
        "product_url": None,
        "image_url": image_url,
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


def created_post_row(image_url=None):
    return (
        10,
        AUTHOR_ID,
        "햇반 24개",
        "https://shop.example/items/1",
        image_url,
        22900,
        24,
        4,
        datetime(2026, 11, 20, tzinfo=timezone.utc),
        "기숙사 1층 로비",
        "KEEP_BY_HOST",
        "RECRUITING",
        datetime(2026, 11, 15, tzinfo=timezone.utc),
    )


class PostRecruitmentResponseTest(unittest.TestCase):
    def test_create_post_stores_server_extracted_image(self):
        connection = FakeConnection(
            [created_post_row("https://cdn.example/image.jpg")]
        )
        post = PostCreateRequest.model_validate(
            {
                "product_name": "햇반 24개",
                "product_url": "https://shop.example/items/1",
                "image_url": "https://client.example/untrusted.jpg",
                "total_price": 22900,
                "total_quantity": 24,
                "host_quantity": 4,
                "deadline": "2026-11-20T12:00:00Z",
                "pickup_location": "기숙사 1층 로비",
                "shortfall_policy": "KEEP_BY_HOST",
            }
        )

        with patch("app.routers.posts.get_connection", return_value=connection), patch(
            "app.routers.posts.fetch_product_metadata",
            return_value=ProductMetadata(None, "https://cdn.example/image.jpg"),
        ):
            result = create_post(post, AUTHOR_ID)

        self.assertEqual(
            connection.cursor_instance.calls[0][1][3],
            "https://cdn.example/image.jpg",
        )
        self.assertEqual(result["data"]["image_url"], "https://cdn.example/image.jpg")
        self.assertNotIn("image_url", PostCreateRequest.model_fields)
        self.assertTrue(
            any(
                "INSERT INTO public.chat_rooms" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_create_post_succeeds_with_null_image_when_metadata_is_missing(self):
        connection = FakeConnection([created_post_row()])
        post = PostCreateRequest(
            product_name="햇반 24개",
            product_url="https://shop.example/items/1",
            total_price=22900,
            total_quantity=24,
            host_quantity=4,
            deadline=datetime(2026, 11, 20, tzinfo=timezone.utc),
            pickup_location="기숙사 1층 로비",
            shortfall_policy="KEEP_BY_HOST",
        )

        with patch("app.routers.posts.get_connection", return_value=connection), patch(
            "app.routers.posts.fetch_product_metadata",
            return_value=ProductMetadata(None, None),
        ):
            result = create_post(post, AUTHOR_ID)

        self.assertIsNone(connection.cursor_instance.calls[0][1][3])
        self.assertIsNone(result["data"]["image_url"])

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

    def test_post_list_preserves_image_url(self):
        connection = FakeConnection([post_row("https://cdn.example/post.png")])

        with patch("app.routers.posts.get_connection", return_value=connection):
            post = get_posts()["data"][0]

        self.assertEqual(post.image_url, "https://cdn.example/post.png")

    def test_post_detail_preserves_image_url(self):
        connection = FakeConnection([post_row("https://cdn.example/post.png")])

        with patch("app.routers.posts.get_connection", return_value=connection):
            post = get_post(10)["data"]

        self.assertEqual(post.image_url, "https://cdn.example/post.png")

    def test_missing_post_returns_not_found(self):
        connection = FakeConnection([])

        with patch("app.routers.posts.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                get_post(999)

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "POST_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
