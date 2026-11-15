import base64
import os
import unittest
from datetime import datetime, timezone
from io import BytesIO
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException, UploadFile

from app.routers.post_images import upload_image
from app.schemas.post_images import PostImageUploadResponse
from app.services.post_image_storage import (
    ImageRecordError,
    ImageTooLargeError,
    InvalidImageError,
    MAX_POST_IMAGE_BYTES,
    PostImageUpload,
    StorageOperationError,
    upload_post_image,
)


USER_ID = UUID("11111111-1111-1111-1111-111111111111")
UPLOAD_ID = UUID("22222222-2222-2222-2222-222222222222")
EXPIRES_AT = datetime(2026, 11, 17, tzinfo=timezone.utc)
ONE_PIXEL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


class FakeCursor:
    def __init__(self, row=None, error=None):
        self.row = row
        self.error = error
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.error is not None:
            raise self.error

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, row=None, error=None):
        self.cursor_instance = FakeCursor(row, error)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self):
        return self.cursor_instance


def storage_environment():
    return {
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_SECRET_KEY": "test-secret-key",
        "SUPABASE_STORAGE_BUCKET": "post-images",
        "DORMN_POST_IMAGE_UPLOAD_TTL_HOURS": "24",
    }


class PostImageUploadTest(unittest.TestCase):
    def test_valid_image_is_uploaded_and_recorded(self):
        connection = FakeConnection(row=(UPLOAD_ID, EXPIRES_AT))

        with patch.dict(os.environ, storage_environment()), patch(
            "app.services.post_image_storage._storage_upload"
        ) as storage_upload, patch(
            "app.services.post_image_storage.get_connection",
            return_value=connection,
        ):
            result = upload_post_image(BytesIO(ONE_PIXEL_PNG), USER_ID)

        storage_path = storage_upload.call_args.args[1]
        self.assertEqual(storage_upload.call_args.args[3], "image/png")
        self.assertTrue(storage_path.startswith(f"tmp/{USER_ID}/"))
        self.assertTrue(storage_path.endswith(".png"))
        self.assertEqual(result.upload_id, UPLOAD_ID)
        self.assertIn(storage_path, result.preview_url)
        self.assertEqual(connection.cursor_instance.calls[0][1][1], USER_ID)

    def test_invalid_file_content_is_rejected_even_with_image_like_input(self):
        with patch.dict(os.environ, storage_environment()), patch(
            "app.services.post_image_storage._storage_upload"
        ) as storage_upload:
            with self.assertRaises(InvalidImageError):
                upload_post_image(BytesIO(b"not-a-png"), USER_ID)

        storage_upload.assert_not_called()

    def test_file_over_5_mib_is_rejected(self):
        with patch.dict(os.environ, storage_environment()), patch(
            "app.services.post_image_storage._storage_upload"
        ) as storage_upload:
            with self.assertRaises(ImageTooLargeError):
                upload_post_image(
                    BytesIO(b"x" * (MAX_POST_IMAGE_BYTES + 1)),
                    USER_ID,
                )

        storage_upload.assert_not_called()

    def test_storage_failure_attempts_orphan_cleanup(self):
        with patch.dict(os.environ, storage_environment()), patch(
            "app.services.post_image_storage._storage_upload",
            side_effect=StorageOperationError("storage unavailable"),
        ), patch(
            "app.services.post_image_storage._storage_remove"
        ) as storage_remove:
            with self.assertRaises(StorageOperationError):
                upload_post_image(BytesIO(ONE_PIXEL_PNG), USER_ID)

        storage_remove.assert_called_once()

    def test_database_failure_attempts_orphan_cleanup(self):
        with patch.dict(os.environ, storage_environment()), patch(
            "app.services.post_image_storage._storage_upload"
        ), patch(
            "app.services.post_image_storage._storage_remove"
        ) as storage_remove, patch(
            "app.services.post_image_storage.get_connection",
            side_effect=RuntimeError("database unavailable"),
        ):
            with self.assertRaises(ImageRecordError):
                upload_post_image(BytesIO(ONE_PIXEL_PNG), USER_ID)

        storage_remove.assert_called_once()

    def test_route_keeps_data_response_envelope(self):
        upload = PostImageUpload(
            upload_id=UPLOAD_ID,
            preview_url="https://example.supabase.co/preview.png",
            expires_at=EXPIRES_AT,
        )

        with patch(
            "app.routers.post_images.upload_post_image",
            return_value=upload,
        ):
            result = upload_image(
                UploadFile(filename="client-name.exe", file=BytesIO(b"ignored")),
                USER_ID,
            )

        self.assertIsInstance(result["data"], PostImageUploadResponse)
        self.assertEqual(result["data"].upload_id, UPLOAD_ID)

    def test_route_maps_storage_failure_without_exposing_details(self):
        with patch(
            "app.routers.post_images.upload_post_image",
            side_effect=StorageOperationError("secret-key=must-not-leak"),
        ):
            with self.assertRaises(HTTPException) as context:
                upload_image(
                    UploadFile(filename="image.png", file=BytesIO(ONE_PIXEL_PNG)),
                    USER_ID,
                )

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.code, "IMAGE_UPLOAD_UNAVAILABLE")
        self.assertNotIn("secret-key", context.exception.message)


if __name__ == "__main__":
    unittest.main()
