from pydantic import BaseModel


class ProductPreviewRequest(BaseModel):
    product_url: str


class ProductPreviewResponse(BaseModel):
    product_url: str
    product_name_suggestion: str | None
    image_url: str | None
