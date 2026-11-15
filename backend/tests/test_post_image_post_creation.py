import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.posts import create_post
from app.schemas.posts import PostCreateRequest
from app.services.product_metadata import ProductMetadata


USER_ID = UUID("11111111-1111-1111-1111-111111111111")
OTHER_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
UPLOAD_ID = UUID("33333333-3333-3333-3333-333333333333")
FUTURE = datetime.now(timezone.utc) + timedelta(hours=1)
PAST = datetime.now(timezone.utc) - timedelta(hours=1)


def post_request(image_upload_id=None, product_url="https://shop.example/item"):
    return PostCreateRequest(
        product_name="햇반 24개",
        product_url=product_url,
        image_upload_id=image_upload_id,
        total_price=22900,
        total_quantity=24,
        host_quantity=4,
        deadline=datetime(2026, 11, 20, tzinfo=timezone.utc),
        pickup_location="기숙사 1층 로비",
        shortfall_policy="KEEP_BY_HOST",
    )


def post_row(image_url):
    return (
        10,
        USER_ID,
        "햇반 24개",
        "https://shop.example/item",
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


class SequenceCursor:
    def __init__(self, rows, error_on_update=False):
        self.rows = list(rows)
        self.error_on_update = error_on_update
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.error_on_update and "UPDATE public.post_image_uploads" in query:
            raise RuntimeError("claim update failed")

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class SequenceConnection:
    def __init__(self, rows, error_on_update=False):
        self.cursor_instance = SequenceCursor(rows, error_on_update)
        self.rolled_back = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.rolled_back = exc_type is not None
        return False

    def cursor(self):
        return self.cursor_instance


class ConcurrentDatabase:
    def __init__(self):
        import threading

        self.lock = threading.Lock()
        self.claimed_post_id = None
        self.next_post_id = 10

    def connection(self):
        return ConcurrentConnection(self)


class ConcurrentConnection:
    def __init__(self, database):
        self.database = database
        self.cursor_instance = ConcurrentCursor(database)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if exc_type is not None and self.cursor_instance.inserted:
            self.database.next_post_id -= 1
        if self.cursor_instance.lock_acquired:
            self.database.lock.release()
        return False

    def cursor(self):
        return self.cursor_instance


class ConcurrentCursor:
    def __init__(self, database):
        self.database = database
        self.lock_acquired = False
        self.inserted = False
        self.pending_row = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        if "FOR UPDATE" in query:
            self.database.lock.acquire()
            self.lock_acquired = True
            self.pending_row = (
                UPLOAD_ID,
                USER_ID,
                "tmp/11111111-1111-1111-1111-111111111111/upload.png",
                FUTURE,
                self.database.claimed_post_id,
            )
        elif query.lstrip().startswith("INSERT INTO posts"):
            self.inserted = True
            self.database.next_post_id += 1
            self.pending_row = post_row("https://cdn.example/upload.png")
        elif "UPDATE public.post_image_uploads" in query:
            if self.database.claimed_post_id is None:
                self.database.claimed_post_id = params[0]
                self.pending_row = (UPLOAD_ID,)
            else:
                self.pending_row = None

    def fetchone(self):
        row = self.pending_row
        self.pending_row = None
        return row


class PostImagePostCreationTest(unittest.TestCase):
    def test_upload_id_creates_post_and_claims_upload_in_one_flow(self):
        upload_row = (
            UPLOAD_ID,
            USER_ID,
            "tmp/11111111-1111-1111-1111-111111111111/upload.png",
            FUTURE,
            None,
        )
        connection = SequenceConnection(
            [upload_row, post_row("https://cdn.example/upload.png"), (UPLOAD_ID,)]
        )

        with patch("app.routers.posts.get_connection", return_value=connection), patch(
            "app.routers.posts.get_public_post_image_url",
            return_value="https://cdn.example/upload.png",
        ), patch(
            "app.routers.posts.fetch_product_metadata",
            side_effect=AssertionError("metadata lookup must be skipped"),
        ):
            result = create_post(post_request(UPLOAD_ID), USER_ID)

        self.assertEqual(result["data"]["image_url"], "https://cdn.example/upload.png")
        self.assertIn("FOR UPDATE", connection.cursor_instance.calls[0][0])
        self.assertIn("claimed_post_id", connection.cursor_instance.calls[-1][0])
        self.assertFalse(connection.rolled_back)

    def test_other_users_upload_is_rejected(self):
        upload_row = (UPLOAD_ID, OTHER_USER_ID, "tmp/other/upload.png", FUTURE, None)
        connection = SequenceConnection([upload_row])

        with patch("app.routers.posts.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                create_post(post_request(UPLOAD_ID), USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "IMAGE_UPLOAD_NOT_OWNED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_expired_upload_is_rejected(self):
        upload_row = (UPLOAD_ID, USER_ID, "tmp/user/upload.png", PAST, None)
        connection = SequenceConnection([upload_row])

        with patch("app.routers.posts.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                create_post(post_request(UPLOAD_ID), USER_ID)

        self.assertEqual(context.exception.code, "IMAGE_UPLOAD_EXPIRED")

    def test_claimed_upload_is_rejected(self):
        upload_row = (UPLOAD_ID, USER_ID, "tmp/user/upload.png", FUTURE, 77)
        connection = SequenceConnection([upload_row])

        with patch("app.routers.posts.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                create_post(post_request(UPLOAD_ID), USER_ID)

        self.assertEqual(context.exception.code, "IMAGE_UPLOAD_ALREADY_USED")

    def test_same_upload_cannot_be_claimed_twice(self):
        database = ConcurrentDatabase()

        def create():
            try:
                return create_post(post_request(UPLOAD_ID), USER_ID)
            except HTTPException as exc:
                return exc

        with patch(
            "app.routers.posts.get_connection",
            side_effect=database.connection,
        ), patch(
            "app.routers.posts.get_public_post_image_url",
            return_value="https://cdn.example/upload.png",
        ), patch(
            "app.routers.posts.fetch_product_metadata",
            side_effect=AssertionError("metadata lookup must be skipped"),
        ):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: create(), range(2)))

        successes = [result for result in results if isinstance(result, dict)]
        conflicts = [
            result
            for result in results
            if isinstance(result, HTTPException)
            and result.code == "IMAGE_UPLOAD_ALREADY_USED"
        ]
        self.assertEqual(len(successes), 1)
        self.assertEqual(len(conflicts), 1)

    def test_claim_failure_rolls_back_post_transaction(self):
        upload_row = (
            UPLOAD_ID,
            USER_ID,
            "tmp/user/upload.png",
            FUTURE,
            None,
        )
        connection = SequenceConnection(
            [upload_row, post_row("https://cdn.example/upload.png")],
            error_on_update=True,
        )

        with patch("app.routers.posts.get_connection", return_value=connection), patch(
            "app.routers.posts.get_public_post_image_url",
            return_value="https://cdn.example/upload.png",
        ):
            with self.assertRaises(RuntimeError):
                create_post(post_request(UPLOAD_ID), USER_ID)

        self.assertTrue(connection.rolled_back)

    def test_without_upload_id_keeps_metadata_extraction(self):
        connection = SequenceConnection([post_row("https://cdn.example/meta.png")])

        with patch("app.routers.posts.get_connection", return_value=connection), patch(
            "app.routers.posts.fetch_product_metadata",
            return_value=ProductMetadata(None, "https://cdn.example/meta.png"),
        ) as fetch_metadata:
            result = create_post(post_request(None), USER_ID)

        fetch_metadata.assert_called_once_with("https://shop.example/item")
        self.assertEqual(result["data"]["image_url"], "https://cdn.example/meta.png")


if __name__ == "__main__":
    unittest.main()
