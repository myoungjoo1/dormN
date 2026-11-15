from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class PostImageUploadResponse(BaseModel):
    upload_id: UUID
    preview_url: str
    expires_at: datetime
