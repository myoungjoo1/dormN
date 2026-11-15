import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app.routers.products import preview_product
from app.schemas.products import ProductPreviewRequest, ProductPreviewResponse
from app.services.product_metadata import (
    BlockedProductUrl,
    InvalidProductUrl,
    ProductMetadata,
)


class ProductPreviewRouteTest(unittest.TestCase):
    def test_preview_reuses_metadata_service_and_data_envelope(self):
        request = ProductPreviewRequest(product_url="https://shop.example/item")

        with patch(
            "app.routers.products.fetch_product_metadata",
            return_value=ProductMetadata("햇반 24개", "https://cdn.example/item.png"),
        ) as fetch_metadata:
            result = preview_product(request)

        fetch_metadata.assert_called_once_with(request.product_url)
        self.assertIsInstance(result["data"], ProductPreviewResponse)
        self.assertEqual(result["data"].image_url, "https://cdn.example/item.png")

    def test_preview_maps_invalid_url_to_common_error(self):
        with patch(
            "app.routers.products.fetch_product_metadata",
            side_effect=InvalidProductUrl("invalid"),
        ):
            with self.assertRaises(HTTPException) as context:
                preview_product(
                    ProductPreviewRequest(product_url="ftp://shop.example/item")
                )

        self.assertEqual(context.exception.status_code, 422)
        self.assertEqual(context.exception.code, "INVALID_PRODUCT_URL")

    def test_preview_maps_blocked_url_to_common_error(self):
        with patch(
            "app.routers.products.fetch_product_metadata",
            side_effect=BlockedProductUrl("blocked"),
        ):
            with self.assertRaises(HTTPException) as context:
                preview_product(
                    ProductPreviewRequest(product_url="http://127.0.0.1/item")
                )

        self.assertEqual(context.exception.status_code, 422)
        self.assertEqual(context.exception.code, "PRODUCT_URL_BLOCKED")


if __name__ == "__main__":
    unittest.main()
