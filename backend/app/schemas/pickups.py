from datetime import datetime

from pydantic import BaseModel


class PickupCompletionResponse(BaseModel):
    participation_id: int
    post_id: int
    pickup_completed_at: datetime
    post_status: str


class PickupParticipantResponse(BaseModel):
    participation_id: int
    room_number: str | None
    quantity: int
    pickup_completed: bool
    pickup_completed_at: datetime | None
