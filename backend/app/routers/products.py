from fastapi import APIRouter

from app.api import ApiException, ApiResponse
from app.schemas.products import ProductPreviewRequest, ProductPreviewResponse
from app.services.product_metadata import (
    BlockedProductUrl,
    InvalidProductUrl,
    fetch_product_metadata,
)


router = APIRouter(prefix="/products", tags=["products"])


@router.post(
    "/preview",
    response_model=ApiResponse[ProductPreviewResponse],
)
def preview_product(request: ProductPreviewRequest):
    try:
        metadata = fetch_product_metadata(request.product_url)
    except InvalidProductUrl as exc:
        raise ApiException(
            422,
            "INVALID_PRODUCT_URL",
            str(exc),
        ) from exc
    except BlockedProductUrl as exc:
        raise ApiException(
            422,
            "PRODUCT_URL_BLOCKED",
            str(exc),
        ) from exc

    return {
        "data": ProductPreviewResponse(
            product_url=request.product_url,
            product_name_suggestion=metadata.product_name_suggestion,
            image_url=metadata.image_url,
        )
    }
