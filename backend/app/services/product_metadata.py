import http.client
import ipaddress
import socket
import ssl
from dataclasses import dataclass
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit


MAX_HTML_BYTES = 1_048_576
MAX_REDIRECTS = 3
REQUEST_TIMEOUT_SECONDS = 5
MAX_PRODUCT_NAME_LENGTH = 200
MAX_IMAGE_URL_LENGTH = 2_048
USER_AGENT = "DormN/1.0 (+product-preview)"


class InvalidProductUrl(ValueError):
    """The URL is not a supported HTTP(S) URL."""


class BlockedProductUrl(ValueError):
    """The URL resolves to an address that must not be fetched."""


class _MetadataFetchError(Exception):
    """A valid URL could not be fetched or read."""


@dataclass(frozen=True)
class ProductMetadata:
    product_name_suggestion: str | None
    image_url: str | None


class _OpenGraphParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title: str | None = None
        self.image: str | None = None
        self.twitter_image: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "meta":
            return

        attributes = {
            key.lower(): value
            for key, value in attrs
            if value is not None
        }
        content = _clean_metadata_value(attributes.get("content"))
        if not content:
            return

        property_name = (attributes.get("property") or "").lower()
        name = (attributes.get("name") or "").lower()
        if property_name == "og:title" and self.title is None:
            self.title = content
        elif property_name == "og:image" and self.image is None:
            self.image = content
        elif name == "twitter:image" and self.twitter_image is None:
            self.twitter_image = content


def extract_product_metadata(html: bytes, product_url: str) -> ProductMetadata:
    """Extract supported metadata without making any additional network request."""
    parser = _OpenGraphParser()
    parser.feed(html.decode("utf-8", errors="replace"))
    parser.close()

    image_value = parser.image or parser.twitter_image
    image_url = _resolve_image_url(image_value, product_url)
    return ProductMetadata(
        product_name_suggestion=_limit_text(parser.title),
        image_url=image_url,
    )


def fetch_product_metadata(product_url: str) -> ProductMetadata:
    """Fetch metadata, returning empty fields for ordinary upstream failures."""
    _validate_product_url(product_url)

    try:
        html, final_url = _fetch_html(product_url)
        if html is None or final_url is None:
            return ProductMetadata(None, None)
        return extract_product_metadata(html, final_url)
    except (InvalidProductUrl, BlockedProductUrl):
        raise
    except Exception:
        # A third-party page must not make the preview endpoint fail with 500.
        return ProductMetadata(None, None)


def _fetch_html(product_url: str) -> tuple[bytes | None, str | None]:
    current_url = product_url

    for redirect_count in range(MAX_REDIRECTS + 1):
        parsed = _validate_product_url(current_url)
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        addresses = _resolve_public_addresses(parsed.hostname, port)

        try:
            status, headers, body = _request_once(parsed, port, addresses)
        except (OSError, TimeoutError, http.client.HTTPException, ssl.SSLError) as exc:
            raise _MetadataFetchError from exc

        if status in {301, 302, 303, 307, 308}:
            if redirect_count >= MAX_REDIRECTS:
                return None, None
            location = headers.get("location")
            if not location:
                return None, None
            current_url = urljoin(current_url, location)
            # The next loop validates both the redirect scheme and its address.
            continue

        if status < 200 or status >= 300:
            return None, None

        content_type = headers.get("content-type", "").lower()
        if content_type and not (
            "text/html" in content_type or "application/xhtml+xml" in content_type
        ):
            return None, None

        content_length = headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > MAX_HTML_BYTES:
                    return None, None
            except ValueError:
                return None, None

        if len(body) > MAX_HTML_BYTES:
            return None, None
        return body, current_url

    return None, None


def _request_once(
    parsed_url,
    port: int,
    addresses: list[str],
) -> tuple[int, dict[str, str], bytes]:
    path = urlunsplit(("", "", parsed_url.path or "/", parsed_url.query, ""))
    last_error: OSError | None = None

    for address in addresses:
        connection = None
        try:
            if parsed_url.scheme == "https":
                connection = _PinnedHTTPSConnection(
                    parsed_url.hostname,
                    port,
                    address,
                    REQUEST_TIMEOUT_SECONDS,
                )
            else:
                connection = _PinnedHTTPConnection(
                    parsed_url.hostname,
                    port,
                    address,
                    REQUEST_TIMEOUT_SECONDS,
                )
            connection.request(
                "GET",
                path,
                headers={
                    "Accept": "text/html,application/xhtml+xml",
                    "Accept-Encoding": "identity",
                    "User-Agent": USER_AGENT,
                },
            )
            response = connection.getresponse()
            headers = {
                key.lower(): value for key, value in response.getheaders()
            }
            body = response.read(MAX_HTML_BYTES + 1)
            return response.status, headers, body
        except OSError as exc:
            last_error = exc
        finally:
            if connection is not None:
                connection.close()

    if last_error is not None:
        raise last_error
    raise OSError("No validated address was available")


class _PinnedHTTPConnection(http.client.HTTPConnection):
    def __init__(self, host: str, port: int, address: str, timeout: int) -> None:
        super().__init__(host, port=port, timeout=timeout)
        self._address = address

    def connect(self) -> None:
        self.sock = socket.create_connection((self._address, self.port), self.timeout)


class _PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host: str, port: int, address: str, timeout: int) -> None:
        super().__init__(host, port=port, timeout=timeout)
        self._address = address

    def connect(self) -> None:
        raw_socket = socket.create_connection(
            (self._address, self.port),
            self.timeout,
        )
        self.sock = self._context.wrap_socket(
            raw_socket,
            server_hostname=self.host,
        )


def _validate_product_url(product_url: str):
    if not isinstance(product_url, str) or not product_url.strip():
        raise InvalidProductUrl("Product URL is required")

    try:
        parsed = urlsplit(product_url.strip())
        port = parsed.port
    except ValueError as exc:
        raise InvalidProductUrl("Product URL has an invalid port") from exc

    if parsed.scheme not in {"http", "https"}:
        raise InvalidProductUrl("Only http and https URLs are supported")
    if not parsed.hostname or parsed.username or parsed.password:
        raise InvalidProductUrl("Product URL must contain a public hostname")
    if port == 0:
        raise InvalidProductUrl("Product URL has an invalid port")

    host = parsed.hostname.rstrip(".").lower()
    if not host or any(ord(character) < 32 for character in host):
        raise InvalidProductUrl("Product URL has an invalid hostname")
    if host == "localhost" or host.endswith(".localhost"):
        raise BlockedProductUrl("Product URL resolves to a blocked address")

    return parsed


def _resolve_public_addresses(host: str | None, port: int | None) -> list[str]:
    if not host:
        raise InvalidProductUrl("Product URL must contain a hostname")

    try:
        direct_ip = ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        direct_ip = None

    if direct_ip is not None:
        if not _is_public_ip(direct_ip):
            raise BlockedProductUrl("Product URL resolves to a blocked address")
        return [host]

    try:
        results = socket.getaddrinfo(
            host,
            port,
            type=socket.SOCK_STREAM,
        )
    except socket.gaierror as exc:
        raise _MetadataFetchError from exc

    addresses: list[str] = []
    for result in results:
        address = result[4][0]
        ip = ipaddress.ip_address(address.split("%", 1)[0])
        if not _is_public_ip(ip):
            raise BlockedProductUrl("Product URL resolves to a blocked address")
        if address not in addresses:
            addresses.append(address)

    if not addresses:
        raise _MetadataFetchError("DNS returned no addresses")
    return addresses


def _is_public_ip(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    return address.is_global


def _resolve_image_url(image_value: str | None, product_url: str) -> str | None:
    if not image_value:
        return None

    try:
        image_url = urljoin(product_url, image_value)
        parsed = urlsplit(image_url)
    except ValueError:
        return None

    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    if parsed.username or parsed.password or len(image_url) > MAX_IMAGE_URL_LENGTH:
        return None
    return image_url


def _clean_metadata_value(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = " ".join(value.split())
    return cleaned or None


def _limit_text(value: str | None) -> str | None:
    if not value:
        return None
    return value[:MAX_PRODUCT_NAME_LENGTH]
