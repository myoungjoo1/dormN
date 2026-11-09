import os
from uuid import UUID

from dotenv import load_dotenv


load_dotenv()


def _development_user_id(name: str, fallback: str) -> UUID:
    # shortcut: fixed UUID fallbacks are only for local tests; replace them with Auth user UUIDs before using the API.
    return UUID(os.getenv(name, fallback))


DEVELOPMENT_HOST_USER_ID = _development_user_id(
    "DORMN_HOST_USER_ID",
    "00000000-0000-0000-0000-000000000001",
)
DEVELOPMENT_PARTICIPANT_USER_ID = _development_user_id(
    "DORMN_PARTICIPANT_USER_ID",
    "00000000-0000-0000-0000-000000000002",
)
