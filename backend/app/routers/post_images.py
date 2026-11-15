from uuid import UUID

from fastapi import APIRouter, Depends, File, UploadFile, status

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.schemas.post_images import PostImageUploadResponse
from app.services.post_image_storage import (
    ImageRecordError,
    ImageTooLargeError,
    InvalidImageError,
    StorageConfigurationError,
    StorageOperationError,
    upload_post_image,
)


router = APIRouter(prefix="/post-images", tags=["post-images"])


@router.post(
    "",
    response_model=ApiResponse[PostImageUploadResponse],
    status_code=status.HTTP_201_CREATED,
)
def upload_image(
    file: UploadFile = File(...),
    current_user_id: UUID = Depends(get_current_user_id),
):
    try:
        upload = upload_post_image(file.file, current_user_id)
    except InvalidImageError as exc:
        raise ApiException(422, "INVALID_IMAGE", str(exc)) from exc
    except ImageTooLargeError as exc:
        raise ApiException(413, "IMAGE_TOO_LARGE", str(exc)) from exc
    except StorageConfigurationError as exc:
        raise ApiException(
            500,
            "STORAGE_CONFIGURATION_ERROR",
            "Storage is not configured",
        ) from exc
    except (StorageOperationError, ImageRecordError) as exc:
        raise ApiException(
            503,
            "IMAGE_UPLOAD_UNAVAILABLE",
            "Image upload service is temporarily unavailable",
        ) from exc

    return {
        "data": PostImageUploadResponse(
            upload_id=upload.upload_id,
            preview_url=upload.preview_url,
            expires_at=upload.expires_at,
        )
    }
