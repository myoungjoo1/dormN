import unittest
from unittest.mock import patch

from app.services.product_metadata import (
    BlockedProductUrl,
    ProductMetadata,
    _fetch_html,
    _resolve_public_addresses,
    extract_product_metadata,
    fetch_product_metadata,
)


class ProductMetadataTest(unittest.TestCase):
    def test_localhost_name_is_rejected_before_dns_resolution(self):
        with patch("app.services.product_metadata.socket.getaddrinfo") as resolve:
            with self.assertRaises(BlockedProductUrl):
                fetch_product_metadata("http://localhost/item")

        resolve.assert_not_called()

    def test_extracts_title_and_resolves_relative_og_image(self):
        html = """
            <html><head>
              <meta property="og:title" content="  햇반 24개입  ">
              <meta property="og:image" content="/images/햇반.jpg">
            </head></html>
        """.encode()

        result = extract_product_metadata(html, "https://shop.example/items/1")

        self.assertEqual(result.product_name_suggestion, "햇반 24개입")
        self.assertEqual(
            result.image_url,
            "https://shop.example/images/햇반.jpg",
        )

    def test_uses_twitter_image_when_og_image_is_missing(self):
        html = b'<meta name="twitter:image" content="https://cdn.example/image.jpg">'

        result = extract_product_metadata(html, "https://shop.example/items/1")

        self.assertEqual(result.image_url, "https://cdn.example/image.jpg")

    def test_blocked_ip_is_rejected(self):
        with self.assertRaises(BlockedProductUrl):
            _resolve_public_addresses("127.0.0.1", 80)

    def test_valid_url_with_upstream_failure_returns_empty_metadata(self):
        with patch(
            "app.services.product_metadata._fetch_html",
            return_value=(None, None),
        ):
            result = fetch_product_metadata("https://shop.example/items/1")

        self.assertEqual(result, ProductMetadata(None, None))

    def test_unexpected_parser_failure_returns_empty_metadata(self):
        with patch(
            "app.services.product_metadata._fetch_html",
            return_value=(b"<html>", "https://shop.example/items/1"),
        ), patch(
            "app.services.product_metadata.extract_product_metadata",
            side_effect=RuntimeError("broken parser"),
        ):
            result = fetch_product_metadata("https://shop.example/items/1")

        self.assertEqual(result, ProductMetadata(None, None))

    def test_redirect_target_is_validated_before_following(self):
        with patch(
            "app.services.product_metadata._resolve_public_addresses",
            side_effect=[["93.184.216.34"], BlockedProductUrl("blocked")],
        ), patch(
            "app.services.product_metadata._request_once",
            return_value=(302, {"location": "http://127.0.0.1/private"}, b""),
        ):
            with self.assertRaises(BlockedProductUrl):
                _fetch_html("https://shop.example/items/1")


if __name__ == "__main__":
    unittest.main()
