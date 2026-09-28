"""Version-specific S3 images -> labels and optional consented reverse geocoding."""
import hashlib
import json
import logging
import math
import os
from urllib.parse import unquote_plus
import boto3

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
rekognition = boto3.client("rekognition")


def coordinates(metadata):
    if metadata.get("location-consent") != "true":
        return None
    try:
        lat, lon = float(metadata["latitude"]), float(metadata["longitude"])
    except (KeyError, ValueError, TypeError) as exc:
        raise ValueError("Consented location requires valid latitude/longitude") from exc
    if not math.isfinite(lat) or not math.isfinite(lon) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("Coordinates are out of range")
    return [lon, lat]


def process(record):
    bucket = record["s3"]["bucket"]["name"]
    obj = record["s3"]["object"]
    key, version = unquote_plus(obj["key"]), obj.get("versionId")
    if bucket != os.environ["MEDIA_BUCKET"] or not key.startswith("input/"):
        raise ValueError("Unexpected input location")
    if not version or version == "null":
        raise ValueError("An immutable S3 version ID is required")
    if not key.lower().endswith((".jpg", ".jpeg", ".png")):
        raise ValueError("Only JPEG/PNG images are supported")
    head = s3.head_object(Bucket=bucket, Key=key, VersionId=version)
    if not 0 < head["ContentLength"] <= 5 * 1024 * 1024:
        raise ValueError("Image exceeds the 5 MiB lab limit or is empty")
    if head.get("ContentType") not in ("image/jpeg", "image/png"):
        raise ValueError("Set the correct image Content-Type during upload")
    result = rekognition.detect_labels(
        Image={"S3Object": {"Bucket": bucket, "Name": key, "Version": version}},
        MaxLabels=20, MinConfidence=80,
    )
    output = {"labels": [{"name": x["Name"], "confidence": x["Confidence"]} for x in result.get("Labels", [])]}
    if os.environ.get("ENABLE_GEOLOCATION", "false") == "true":
        position = coordinates(head.get("Metadata", {}))
        if position is not None:
            response = boto3.client("geo-places").reverse_geocode(QueryPosition=position, MaxResults=1, IntendedUse="Storage")
            # Retain only coarse locality, never coordinates or full street address.
            items = response.get("ResultItems", [])
            address = items[0].get("Address", {}) if items else {}
            output["location"] = {"country": address.get("Country", {}).get("Code2"), "locality": address.get("Locality")}
    digest = hashlib.sha256(json.dumps([bucket, key, version]).encode()).hexdigest()
    s3.put_object(Bucket=bucket, Key=f"results/{digest}.json", Body=json.dumps(output).encode(), ContentType="application/json", ServerSideEncryption="AES256")


def handler(event, context):
    failures = []
    for message in event.get("Records", []):
        try:
            body = json.loads(message["body"])
            if body.get("Event") == "s3:TestEvent":
                continue
            records = body.get("Records")
            if not isinstance(records, list) or not records:
                raise ValueError("Expected S3 event records")
            for record in records:
                process(record)
        except Exception as exc:
            # Do not log keys, coordinates, metadata, payloads or exception messages.
            log.warning("media_processing_failed type=%s", type(exc).__name__)
            failures.append({"itemIdentifier": message["messageId"]})
    return {"batchItemFailures": failures}
