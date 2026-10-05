from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class PostCreateRequest(BaseModel):
    product_name: str = Field(max_length=200)
    product_url: str | None = None
    image_url: str | None = None
    total_price: int = Field(gt=0)
    total_quantity: int = Field(gt=0)
    host_quantity: int = Field(ge=1)
    deadline: datetime
    pickup_location: str = Field(max_length=200)
    shortfall_policy: Literal["KEEP_BY_HOST", "CANCEL_IF_SHORT"]

    @model_validator(mode="after")
    def validate_quantities(self):
        if self.host_quantity > self.total_quantity:
            raise ValueError("host_quantity must be less than or equal to total_quantity")
        return self


class PostResponse(BaseModel):
    id: int
    author_id: int
    product_name: str
    product_url: str | None
    image_url: str | None
    total_price: int
    total_quantity: int
    host_quantity: int
    deadline: datetime
    pickup_location: str
    shortfall_policy: str
    status: str
    created_at: datetime
