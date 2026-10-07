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
