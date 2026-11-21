from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.posts import PostRecruitmentResponse


class ParticipationCreateRequest(BaseModel):
    quantity: int = Field(ge=1)


class ParticipationResponse(BaseModel):
    id: int
    post_id: int
    user_id: UUID
    quantity: int
    created_at: datetime


class ParticipationQuoteResponse(BaseModel):
    post_id: int
    quantity: int
    estimated_amount: int
    remaining_quantity_after_join: int


class MyParticipationResponse(BaseModel):
    is_joined: bool
    participation_id: int | None
    quantity: int | None


class MyParticipationHistoryResponse(PostRecruitmentResponse):
    participation_id: int
    quantity: int
    settlement_id: int | None
    settlement_amount: int | None
    payment_status: str | None
    pickup_completed_at: datetime | None
