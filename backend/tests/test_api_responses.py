import asyncio
import json
import unittest

from fastapi.exceptions import RequestValidationError

from app.api import ApiException, http_exception_handler, validation_exception_handler
from app.main import hello


class ApiResponseTest(unittest.TestCase):
    def test_success_response_uses_data_envelope(self):
        self.assertEqual(hello(), {"data": {"message": "DormN"}})

    def test_http_error_uses_error_envelope(self):
        response = asyncio.run(
            http_exception_handler(
                None,
                ApiException(401, "AUTH_REQUIRED", "Authentication required"),
            )
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(
            json.loads(response.body),
            {
                "error": {
                    "code": "AUTH_REQUIRED",
                    "message": "Authentication required",
                }
            },
        )

    def test_validation_error_has_machine_readable_details(self):
        exception = RequestValidationError(
            [
                {
                    "type": "int_parsing",
                    "loc": ("path", "post_id"),
                    "msg": "Input should be a valid integer",
                    "input": "not-an-integer",
                }
            ]
        )
        response = asyncio.run(validation_exception_handler(None, exception))

        self.assertEqual(response.status_code, 422)
        body = json.loads(response.body)
        self.assertEqual(body["error"]["code"], "VALIDATION_ERROR")
        self.assertEqual(body["error"]["details"][0]["field"], "path.post_id")


if __name__ == "__main__":
    unittest.main()
