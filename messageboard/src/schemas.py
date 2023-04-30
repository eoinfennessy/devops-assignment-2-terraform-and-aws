from typing import Union
from pydantic import BaseModel


class MessageCreate(BaseModel):
    author: str
    body: str


class Message(MessageCreate):
    id: int

    class Config:
        orm_mode = True


class ImageCreate(BaseModel):
    filename: str
    raw_img_src: str
    processed_img_src: str


class Image(ImageCreate):
    id: int

    class Config:
        orm_mode = True


class LoadBalancerTestResponse(BaseModel):
    trace_id: Union[str, None]
    instance_id: str


class HealthCheckResponse(BaseModel):
    is_healthy: bool
