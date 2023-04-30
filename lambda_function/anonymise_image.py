from typing import Any
import boto3
import cv2
from dataclasses import dataclass
import httpx
import json
import logging
import numpy as np
import os


logger = logging.getLogger()
logger.setLevel(logging.INFO)

S3 = boto3.resource("s3")
PROCESSED_BUCKET = S3.Bucket(os.environ["PROCESSED_BUCKET_NAME"])
NEURAL_NET = cv2.dnn.readNet(
    "./model/deploy.prototxt",
    "./model/res10_300x300_ssd_iter_140000_fp16.caffemodel"
)


@dataclass(frozen=True)
class ImageSubsection:
    pixels: np.ndarray
    start_x: int
    start_y: int
    end_x: int
    end_y: int


def upload_img(img: np.ndarray, name: str, bucket: Any):
    logger.info(f"Uploading processed image {name} to bucket {bucket.name}")
    img_bytes = cv2.imencode('.jpg', img)[1].tobytes()
    bucket.put_object(Key=name, Body=img_bytes, ContentType="image/jpeg", ACL="public-read")


def blur_face(img: np.ndarray, blur_factor: float = 2.0) -> np.ndarray:
	# calculate kernel sizes based on image dimensions and blur factor
	image_height, image_width = img.shape[:2]
	kernel_width = round(image_width / blur_factor)
	kernel_height = round(image_height / blur_factor)

    # ensure kernel widths are odd
	if kernel_width % 2 == 0:
		kernel_width -= 1
	if kernel_height % 2 == 0:
		kernel_height -= 1
                
	return cv2.GaussianBlur(img, ksize=(kernel_width, kernel_height), sigmaX=0)


def detect_faces(img: np.ndarray, net: Any, confidence_threshold: float = 0.6) -> list[ImageSubsection]:
    blob = cv2.dnn.blobFromImage(img, size=(300, 300), mean=(103.93, 116.77, 123.68))
    net.setInput(blob)
    detections: np.ndarray = net.forward()

    h, w = img.shape[:2]
    faces = []
    for i in range(detections.shape[2]):
        confidence = detections[0, 0, i, 2]
        if confidence < confidence_threshold:
             break
        
        bounding_box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
        start_x, start_y, end_x, end_y = bounding_box.round(0).astype("int")
        faces.append(ImageSubsection(img[start_y:end_y, start_x:end_x], start_x, start_y, end_x, end_y))
    return faces


def load_img(file: bytes) -> np.ndarray:
    img_np = np.frombuffer(file, np.uint8)
    return cv2.imdecode(img_np, cv2.IMREAD_UNCHANGED)


def get_s3_object(bucket_name: str, object_key: str):
    return httpx.get(f"https://{bucket_name}.s3.amazonaws.com/{object_key}")


def get_s3_event_records(event: dict) -> list[dict]:
    s3_event_records = []
    logger.info(f"SQS event: {event}")
    for sqs_record in event["Records"]:
        s3_event = json.loads(sqs_record["body"])
        logger.info(f"S3 event: {s3_event}")
        if s3_event.get("Event") == "s3:TestEvent":
            continue
        s3_event_records += s3_event["Records"]
    return s3_event_records


def lambda_handler(event, context):
    try:
        s3_event_records = get_s3_event_records(event)
        for record in s3_event_records:
            res = get_s3_object(record["s3"]["bucket"]["name"], record["s3"]["object"]["key"])
            img = load_img(res.content)
            faces = detect_faces(img, NEURAL_NET)
            logger.info(f"Detected {len(faces)} faces in image")
            
            for face in faces:
                blurred_face = blur_face(face.pixels)
                img[face.start_y:face.end_y, face.start_x:face.end_x] = blurred_face
            upload_img(img, record["s3"]["object"]["key"], PROCESSED_BUCKET)
            logger.info(f"Successfully uploaded anonymised image to processed bucket")
    except BaseException as err:
        logger.error(f"Exception: {err}")
        raise err
