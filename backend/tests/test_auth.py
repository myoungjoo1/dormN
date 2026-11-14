import json
import unittest
from io import BytesIO
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.auth import get_current_user_id


USER_ID = UUID("11111111-1111-1111-1111-111111111111")


class FakeResponse(BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False


class FakeCursor:
    def __init__(self):
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))


class FakeConnection:
    def __init__(self):
        self.cursor_instance = FakeCursor()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self):
        return self.cursor_instance


class AuthTest(unittest.TestCase):
    def test_missing_credentials_returns_401(self):
        with self.assertRaises(HTTPException) as context:
            get_current_user_id(None)

        self.assertEqual(context.exception.status_code, 401)
        self.assertEqual(context.exception.code, "AUTH_REQUIRED")

    def test_valid_token_returns_uuid_and_creates_profile(self):
        connection = FakeConnection()
        response = FakeResponse(json.dumps({"id": str(USER_ID)}).encode())
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="test-access-token",
        )

        with patch.dict(
            "os.environ",
            {
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "publishable-key",
            },
        ), patch("app.auth.urlopen", return_value=response) as open_url, patch(
            "app.auth.get_connection", return_value=connection
        ):
            result = get_current_user_id(credentials)

        self.assertEqual(result, USER_ID)
        self.assertEqual(
            connection.cursor_instance.calls[0][1],
            (USER_ID,),
        )
        request = open_url.call_args.args[0]
        self.assertEqual(request.full_url, "https://example.supabase.co/auth/v1/user")
        self.assertEqual(request.get_header("Authorization"), "Bearer test-access-token")


if __name__ == "__main__":
    unittest.main()
