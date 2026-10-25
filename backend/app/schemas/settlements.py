from datetime import datetime

from pydantic import BaseModel


class SettlementResponse(BaseModel):
    id: int
    participation_id: int
    amount: int
    payment_status: str
    sent_at: datetime | None
    confirmed_at: datetime | None
    created_at: datetime


class HostSettlementParticipantResponse(BaseModel):
    settlement_id: int | None
    user_id: int
    room_number: str | None
    quantity: int
    amount: int | None
    payment_status: str | None
    sent_at: datetime | None
    confirmed_at: datetime | None


class HostSettlementListResponse(BaseModel):
    post_id: int
    status: str
    total_price: int
    participant_total_amount: int
    host_amount: int
    participants: list[HostSettlementParticipantResponse]
