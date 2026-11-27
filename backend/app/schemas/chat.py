from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class ChatRoomResponse(BaseModel):
    id: int
    room_type: Literal["GROUP", "DM"]
    post_id: int | None
    product_name: str | None
    other_user_id: UUID | None
    other_user_room_number: str | None
    created_at: datetime


def _strip_message(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("body must be a string")
    value = value.strip()
    if not value:
        raise ValueError("body must not be blank")
    return value


class ChatMessageCreateRequest(BaseModel):
    body: str = Field(min_length=1, max_length=2000)

    @field_validator("body", mode="before")
    @classmethod
    def trim_body(cls, value: object) -> str:
        return _strip_message(value)


class ChatMessageResponse(BaseModel):
    id: int
    sender_id: UUID | None
    sender_room_number: str | None
    message_type: Literal["USER", "SYSTEM"]
    body: str
    created_at: datetime
    deleted_at: datetime | None = None
