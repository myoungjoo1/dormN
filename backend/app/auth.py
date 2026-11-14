import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import UUID

from dotenv import load_dotenv
from fastapi import Depends, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.api import ApiException
from app.database import get_connection


load_dotenv()

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> UUID:
    if credentials is None:
        raise ApiException(
            status.HTTP_401_UNAUTHORIZED,
            "AUTH_REQUIRED",
            "Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv("SUPABASE_ANON_KEY")
    if not supabase_url or not supabase_key:
        raise ApiException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "AUTH_CONFIGURATION_ERROR",
            "Supabase Auth is not configured",
        )

    request = Request(
        f"{supabase_url.rstrip('/')}/auth/v1/user",
        headers={
            "Authorization": f"Bearer {credentials.credentials}",
            "apikey": supabase_key,
        },
    )

    try:
        with urlopen(request, timeout=5) as response:
            payload = json.load(response)
    except HTTPError as exc:
        if exc.code in (401, 403):
            raise ApiException(
                status.HTTP_401_UNAUTHORIZED,
                "INVALID_ACCESS_TOKEN",
                "Invalid or expired access token",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc
        raise ApiException(
            status.HTTP_502_BAD_GATEWAY,
            "AUTH_VALIDATION_FAILED",
            "Supabase Auth validation failed",
        ) from exc
    except (URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise ApiException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "AUTH_SERVICE_UNAVAILABLE",
            "Supabase Auth is unavailable",
        ) from exc

    try:
        user_id = UUID(payload["id"])
    except (KeyError, ValueError, TypeError) as exc:
        raise ApiException(
            status.HTTP_401_UNAUTHORIZED,
            "INVALID_AUTH_USER",
            "Supabase Auth returned an invalid user",
        ) from exc

    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO public.users (id)
                VALUES (%s)
                ON CONFLICT (id) DO NOTHING
                """,
                (user_id,),
            )

    return user_id
