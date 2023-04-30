from sqlalchemy import Column, Integer, String

from .database import Base


class Message(Base):
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    author = Column(String, index=True)
    body = Column(String, index=True)


class Image(Base):
    __tablename__ = "images"

    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String, index=True)
    raw_img_src = Column(String, index=True)
    processed_img_src = Column(String, index=True)
