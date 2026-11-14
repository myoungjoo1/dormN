from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


ROOM_NUMBER_PATTERN = r"^[0-9]{3,4}-[1-9][0-9]*$"


class UserUpdateRequest(BaseModel):
    room_number: str = Field(
        min_length=5,
        max_length=20,
        pattern=ROOM_NUMBER_PATTERN,
    )


class UserResponse(BaseModel):
    id: UUID
    room_number: str | None
    dorm_verified: bool
    dorm_verified_at: datetime | None
    created_at: datetime
