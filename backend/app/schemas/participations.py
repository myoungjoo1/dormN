from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


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
