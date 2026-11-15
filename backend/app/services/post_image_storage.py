import logging
import os
import tempfile
import warnings
from dataclasses import dataclass
from datetime import datetime
from pathlib import PurePosixPath
from typing import BinaryIO
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import UUID, uuid4

from PIL import Image, UnidentifiedImageError

from app.database import get_connection


logger = logging.getLogger(__name__)

MAX_POST_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000
READ_CHUNK_BYTES = 64 * 1024
STORAGE_TIMEOUT_SECONDS = 10
DEFAULT_STORAGE_BUCKET = "post-images"
DEFAULT_UPLOAD_TTL_HOURS = 24
ALLOWED_FORMATS = {
    "JPEG": ("image/jpeg", "jpg"),
    "PNG": ("image/png", "png"),
    "WEBP": ("image/webp", "webp"),
}


class PostImageUploadError(Exception):
    """Base class for expected post-image upload failures."""


class InvalidImageError(PostImageUploadError):
    pass


class ImageTooLargeError(PostImageUploadError):
    pass


class StorageConfigurationError(PostImageUploadError):
    pass


class StorageOperationError(PostImageUploadError):
    pass


class ImageRecordError(PostImageUploadError):
    pass


@dataclass(frozen=True)
class StorageConfig:
    supabase_url: str
    secret_key: str
    bucket: str
    ttl_hours: int


@dataclass(frozen=True)
class PostImageUpload:
    upload_id: UUID
    preview_url: str
    expires_at: datetime


def upload_post_image(file_object: BinaryIO, user_id: UUID) -> PostImageUpload:
    """Validate, upload, and register one temporary post image."""
    config = _load_storage_config()

    with tempfile.TemporaryFile(mode="w+b") as temporary_file:
        size_bytes = _copy_with_limit(file_object, temporary_file)
        content_type, extension = _validate_image(temporary_file)

        upload_id = uuid4()
        storage_path = str(
            PurePosixPath("tmp")
            / str(user_id)
            / f"{upload_id}.{extension}"
        )

        temporary_file.seek(0)
        payload = temporary_file.read(MAX_POST_IMAGE_BYTES + 1)
        try:
            _storage_upload(config, storage_path, payload, content_type)
        except StorageOperationError:
            _try_remove_orphan(config, storage_path)
            raise

        try:
            upload_row = _insert_upload_record(
                upload_id=upload_id,
                user_id=user_id,
                storage_path=storage_path,
                content_type=content_type,
                size_bytes=size_bytes,
                ttl_hours=config.ttl_hours,
            )
        except Exception as exc:
            _try_remove_orphan(config, storage_path)
            raise ImageRecordError(
                "Post image upload could not be registered"
            ) from exc

    return PostImageUpload(
        upload_id=upload_row[0],
        preview_url=_public_url(config, storage_path),
        expires_at=upload_row[1],
    )


def _copy_with_limit(source: BinaryIO, destination: BinaryIO) -> int:
    total = 0
    while True:
        try:
            chunk = source.read(READ_CHUNK_BYTES)
        except (OSError, ValueError) as exc:
            raise InvalidImageError("Uploaded file could not be read") from exc
        if not chunk:
            break
        if not isinstance(chunk, bytes):
            raise InvalidImageError("Uploaded file is not binary data")
        total += len(chunk)
        if total > MAX_POST_IMAGE_BYTES:
            raise ImageTooLargeError("Image must be 5 MiB or smaller")
        destination.write(chunk)

    if total == 0:
        raise InvalidImageError("Uploaded file is empty")
    return total


def _validate_image(file_object: BinaryIO) -> tuple[str, str]:
    file_object.seek(0)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(file_object) as image:
                image_format = (image.format or "").upper()
                if image_format not in ALLOWED_FORMATS:
                    raise InvalidImageError(
                        "Only JPEG, PNG, and WebP images are supported"
                    )

                width, height = image.size
                if width <= 0 or height <= 0:
                    raise InvalidImageError("Image dimensions are invalid")
                if width * height > MAX_IMAGE_PIXELS:
                    raise InvalidImageError("Image dimensions are too large")
                if getattr(image, "n_frames", 1) > 1:
                    raise InvalidImageError("Animated images are not supported")

                image.verify()
    except InvalidImageError:
        raise
    except (
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        UnidentifiedImageError,
        OSError,
        SyntaxError,
        ValueError,
        EOFError,
        MemoryError,
    ) as exc:
        raise InvalidImageError("Uploaded file is not a valid image") from exc

    return ALLOWED_FORMATS[image_format]


def _insert_upload_record(
    *,
    upload_id: UUID,
    user_id: UUID,
    storage_path: str,
    content_type: str,
    size_bytes: int,
    ttl_hours: int,
):
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO public.post_image_uploads (
                    id,
                    user_id,
                    storage_path,
                    content_type,
                    size_bytes,
                    expires_at
                )
                VALUES (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    NOW() + (%s * INTERVAL '1 hour')
                )
                RETURNING id, expires_at
                """,
                (
                    upload_id,
                    user_id,
                    storage_path,
                    content_type,
                    size_bytes,
                    ttl_hours,
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise ImageRecordError("Post image upload could not be registered")
    return row


def _load_storage_config() -> StorageConfig:
    supabase_url = os.getenv("SUPABASE_URL")
    secret_key = os.getenv("SUPABASE_SECRET_KEY")
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", DEFAULT_STORAGE_BUCKET)
    ttl_value = os.getenv(
        "DORMN_POST_IMAGE_UPLOAD_TTL_HOURS",
        str(DEFAULT_UPLOAD_TTL_HOURS),
    )

    if not supabase_url or not secret_key or not bucket:
        raise StorageConfigurationError("Storage is not configured")
    try:
        ttl_hours = int(ttl_value)
    except (TypeError, ValueError) as exc:
        raise StorageConfigurationError("Storage upload lifetime is invalid") from exc
    if ttl_hours <= 0:
        raise StorageConfigurationError("Storage upload lifetime is invalid")

    return StorageConfig(
        supabase_url=supabase_url.rstrip("/"),
        secret_key=secret_key,
        bucket=bucket,
        ttl_hours=ttl_hours,
    )


def _storage_object_url(config: StorageConfig, storage_path: str) -> str:
    bucket = quote(config.bucket, safe="")
    path = quote(storage_path, safe="/")
    return f"{config.supabase_url}/storage/v1/object/{bucket}/{path}"


def _public_url(config: StorageConfig, storage_path: str) -> str:
    bucket = quote(config.bucket, safe="")
    path = quote(storage_path, safe="/")
    return f"{config.supabase_url}/storage/v1/object/public/{bucket}/{path}"


def _storage_headers(config: StorageConfig, content_type: str | None = None):
    headers = {
        "apikey": config.secret_key,
        "Authorization": f"Bearer {config.secret_key}",
    }
    if content_type is not None:
        headers["Content-Type"] = content_type
    return headers


def _storage_upload(
    config: StorageConfig,
    storage_path: str,
    payload: bytes,
    content_type: str,
) -> None:
    request = Request(
        _storage_object_url(config, storage_path),
        data=payload,
        headers={
            **_storage_headers(config, content_type),
            "Cache-Control": "31536000",
            "x-upsert": "false",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=STORAGE_TIMEOUT_SECONDS) as response:
            response.read()
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise StorageOperationError("Storage upload failed") from exc


def _storage_remove(config: StorageConfig, storage_path: str) -> None:
    request = Request(
        _storage_object_url(config, storage_path),
        headers=_storage_headers(config),
        method="DELETE",
    )
    try:
        with urlopen(request, timeout=STORAGE_TIMEOUT_SECONDS) as response:
            response.read()
    except HTTPError as exc:
        if exc.code == 404:
            return
        raise StorageOperationError("Storage cleanup failed") from exc
    except (URLError, TimeoutError, OSError) as exc:
        raise StorageOperationError("Storage cleanup failed") from exc


def _try_remove_orphan(config: StorageConfig, storage_path: str) -> None:
    try:
        _storage_remove(config, storage_path)
    except Exception:
        logger.exception("Failed to remove orphaned post image path=%s", storage_path)
