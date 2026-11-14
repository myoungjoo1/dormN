import logging
from typing import Any, Generic, TypeVar

from fastapi import HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException


logger = logging.getLogger(__name__)
DataT = TypeVar("DataT")


class ApiResponse(BaseModel, Generic[DataT]):
    data: DataT


class ApiError(BaseModel):
    code: str
    message: str
    details: list[dict[str, str]] | None = None


class ErrorResponse(BaseModel):
    error: ApiError


class ApiException(HTTPException):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        headers: dict[str, str] | None = None,
    ):
        super().__init__(status_code=status_code, detail=message, headers=headers)
        self.code = code
        self.message = message


COMMON_ERROR_RESPONSES = {
    status_code: {"model": ErrorResponse}
    for status_code in (400, 401, 403, 404, 409, 422, 500, 502, 503)
}


def _error_content(
    code: str,
    message: str,
    details: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    return {"error": error}


async def http_exception_handler(
    request: Request,
    exception: StarletteHTTPException,
) -> JSONResponse:
    del request
    code = getattr(exception, "code", None) or {
        400: "BAD_REQUEST",
        401: "AUTH_REQUIRED",
        403: "FORBIDDEN",
        404: "NOT_FOUND",
        409: "CONFLICT",
    }.get(exception.status_code, "HTTP_ERROR")
    message = getattr(exception, "message", None) or str(exception.detail)
    return JSONResponse(
        status_code=exception.status_code,
        content=_error_content(code, message),
        headers=exception.headers,
    )


async def validation_exception_handler(
    request: Request,
    exception: RequestValidationError,
) -> JSONResponse:
    del request
    details = [
        {
            "field": ".".join(str(part) for part in error["loc"]),
            "message": error["msg"],
        }
        for error in exception.errors()
    ]
    return JSONResponse(
        status_code=422,
        content=_error_content(
            "VALIDATION_ERROR",
            "Request validation failed",
            details,
        ),
    )


async def unhandled_exception_handler(
    request: Request,
    exception: Exception,
) -> JSONResponse:
    logger.error(
        "Unhandled API error for %s",
        request.url.path,
        exc_info=(type(exception), exception, exception.__traceback__),
    )
    return JSONResponse(
        status_code=500,
        content=_error_content(
            "INTERNAL_SERVER_ERROR",
            "An unexpected server error occurred",
        ),
    )
