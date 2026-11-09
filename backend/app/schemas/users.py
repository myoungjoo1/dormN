from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class UserResponse(BaseModel):
    id: UUID
    room_number: str | None
    dorm_verified: bool
    dorm_verified_at: datetime | None
    created_at: datetime
