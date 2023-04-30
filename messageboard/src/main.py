import boto3
from fastapi import Depends, FastAPI, HTTPException, UploadFile
import httpx
import logging
import os
from sqlalchemy.orm import Session
from typing import List, Union

from . import crud, models, schemas
from .database import SessionLocal, engine

logging.basicConfig(
    level="INFO",
    format="%(asctime)s  [%(levelname)-8s]   %(message)s",
    handlers=[
        logging.FileHandler("./logs/devops.log"),
        logging.StreamHandler(),
    ],
)

s3 = boto3.resource("s3")
raw_bucket_name = os.environ.get("AWS_RAW_BUCKET_NAME")
processed_bucket_name = os.environ.get("AWS_PROCESSED_BUCKET_NAME")
raw_bucket = s3.Bucket(raw_bucket_name)

models.Base.metadata.create_all(bind=engine)

res = httpx.get("http://169.254.169.254/latest/meta-data/instance-id")
INSTANCE_ID = res.text

app = FastAPI()


# SQL Alchemy session dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/", response_model=schemas.HealthCheckResponse)
def health_check():
    return {"is_healthy": True}


@app.post("/message/", response_model=schemas.Message)
def create_message(message: schemas.MessageCreate, db: Session = Depends(get_db)):
    return crud.create_message(db=db, message=message)


@app.get("/messages/", response_model=List[schemas.Message])
def read_messages(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.get_messages(db, skip=skip, limit=limit)


@app.get("/message/{message_id}", response_model=schemas.Message)
def read_message(message_id: int, db: Session = Depends(get_db)):
    db_message = crud.get_message(db, message_id=message_id)
    if db_message is None:
        raise HTTPException(status_code=404, detail="Message not found")
    return db_message


@app.get("/load-balancer-test/", response_model=schemas.LoadBalancerTestResponse)
def test_load_balancer(trace_id: Union[str, None] = None):
    logging.info(f'Received request with trace ID: "{trace_id}"')
    return {
	"trace_id": trace_id,
        "instance_id": INSTANCE_ID,
    }


@app.post("/image/", response_model=schemas.Image)
def upload_and_create_image(file: UploadFile, db: Session = Depends(get_db)):
    raw_bucket.put_object(Key=file.filename, Body=file.file, ContentType="image/jpeg", ACL="public-read")
    raw_img_src = f"https://{raw_bucket_name}.s3.amazonaws.com/{file.filename}"
    processed_img_src = f"https://{processed_bucket_name}.s3.amazonaws.com/{file.filename}"
    return crud.create_image(
        db=db,
        image={
            "filename": file.filename,
            "raw_img_src": raw_img_src,
            "processed_img_src": processed_img_src,
        },
    )


@app.get("/images/", response_model=List[schemas.Image])
def read_images(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.get_images(db, skip=skip, limit=limit)


@app.get("/image/{image_id}", response_model=schemas.Image)
def read_image(image_id: int, db: Session = Depends(get_db)):
    db_image = crud.get_image(db, image_id=image_id)
    if db_image is None:
        raise HTTPException(status_code=404, detail="Image not found")
    return db_image
