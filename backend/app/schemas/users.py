from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


ROOM_NUMBER_PATTERN = r"^[0-9]{3,4}-[1-9][0-9]*$"


class UserUpdateRequest(BaseModel):
    room_number: str = Field(
        min_length=5,
        max_length=20,
        pattern=ROOM_NUMBER_PATTERN,
    )


def _strip_required_text(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("value must be a string")
    value = value.strip()
    if not value:
        raise ValueError("value must not be blank")
    return value


class SettlementAccountRequest(BaseModel):
    bank_name: str = Field(max_length=100)
    account_number: str = Field(max_length=100)
    account_holder_name: str = Field(max_length=100)

    @field_validator("bank_name", "account_number", "account_holder_name", mode="before")
    @classmethod
    def trim_required_text(cls, value: object) -> str:
        return _strip_required_text(value)


class SettlementAccountResponse(BaseModel):
    bank_name: str
    account_number: str
    account_holder_name: str
    updated_at: datetime


class UserResponse(BaseModel):
    id: UUID
    room_number: str | None
    dorm_verified: bool
    dorm_verified_at: datetime | None
    created_at: datetime


class UserSearchResponse(BaseModel):
    user_id: UUID
    room_number: str
