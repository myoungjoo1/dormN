import math
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


class LocationCheckRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_meters: float = Field(ge=0)

    @field_validator("latitude", "longitude", "accuracy_meters", mode="before")
    @classmethod
    def require_finite_number(cls, value: object) -> float:
        try:
            parsed = float(value)
        except (TypeError, ValueError) as exc:
            raise ValueError("value must be a finite number") from exc
        if not math.isfinite(parsed):
            raise ValueError("value must be a finite number")
        return parsed


class LocationVerificationResponse(BaseModel):
    status: str
    valid_check_count: int
    required_check_count: int
    first_valid_check_at: datetime | None
    last_valid_check_at: datetime | None
    last_check_at: datetime | None
    dwell_seconds: int
    minimum_dwell_seconds: int
    dwell_satisfied: bool
    interval_satisfied: bool
    additional_check_required: bool
    eligible_time_start: str
    eligible_time_end: str
    eligible_time_zone: str
    next_check_at: datetime | None
    message: str | None = None


class UserSearchResponse(BaseModel):
    user_id: UUID
    room_number: str
