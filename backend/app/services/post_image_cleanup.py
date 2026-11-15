import logging
from dataclasses import dataclass
from uuid import UUID

from app.database import get_connection
from app.services.post_image_storage import (
    PostImageUploadError,
    delete_post_image_storage,
)


logger = logging.getLogger(__name__)
DEFAULT_CLEANUP_LIMIT = 100
MAX_CLEANUP_LIMIT = 1_000


@dataclass(frozen=True)
class CleanupSummary:
    processed: int
    deleted: int
    skipped: int
    failed: int


def cleanup_expired_post_images(
    max_items: int = DEFAULT_CLEANUP_LIMIT,
) -> CleanupSummary:
    if not 1 <= max_items <= MAX_CLEANUP_LIMIT:
        raise ValueError(
            f"max_items must be between 1 and {MAX_CLEANUP_LIMIT}"
        )

    upload_ids = _find_expired_upload_ids(max_items)
    deleted = 0
    skipped = 0
    failed = 0

    for upload_id in upload_ids:
        try:
            result = _cleanup_one(upload_id)
        except Exception:
            # One bad row must not prevent later candidates from being attempted.
            logger.exception("Post image cleanup failed")
            failed += 1
            continue

        if result == "deleted":
            deleted += 1
        elif result == "skipped":
            skipped += 1
        else:
            failed += 1

    return CleanupSummary(
        processed=len(upload_ids),
        deleted=deleted,
        skipped=skipped,
        failed=failed,
    )


def _find_expired_upload_ids(max_items: int) -> list[UUID]:
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id
                FROM public.post_image_uploads
                WHERE claimed_post_id IS NULL
                  AND expires_at < NOW()
                ORDER BY expires_at, id
                LIMIT %s
                """,
                (max_items,),
            )
            return [row[0] for row in cursor.fetchall()]


def _cleanup_one(upload_id: UUID) -> str:
    # Keep the row lock while deleting the object. This prevents POST /posts
    # from claiming the same row between the eligibility check and deletion.
    # shortcut: one row can wait for the 10s Storage timeout; use a DB lease
    # column before increasing cleanup concurrency or the per-run limit.
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id, storage_path
                FROM public.post_image_uploads
                WHERE id = %s
                  AND claimed_post_id IS NULL
                  AND expires_at < NOW()
                FOR UPDATE
                """,
                (upload_id,),
            )
            row = cursor.fetchone()
            if row is None:
                return "skipped"

            try:
                delete_post_image_storage(row[1])
            except PostImageUploadError:
                return "failed"

            cursor.execute(
                """
                DELETE FROM public.post_image_uploads
                WHERE id = %s
                  AND claimed_post_id IS NULL
                  AND expires_at < NOW()
                RETURNING id
                """,
                (upload_id,),
            )
            if cursor.fetchone() is None:
                # The Storage object is already gone, so leave the row for a
                # later retry if the database delete did not take effect.
                raise RuntimeError("Post image upload record was not deleted")

    return "deleted"
