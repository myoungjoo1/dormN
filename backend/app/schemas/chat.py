from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel


class ChatRoomResponse(BaseModel):
    id: int
    room_type: Literal["GROUP", "DM"]
    post_id: int | None
    product_name: str | None
    other_user_id: UUID | None
    other_user_room_number: str | None
    created_at: datetime
