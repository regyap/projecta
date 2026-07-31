import hashlib
import hmac
import json
import os
import time
from typing import Any

import boto3

DDB_TABLE = os.environ["DDB_TABLE"]
EVENT_BUS_NAME = os.environ["EVENT_BUS_NAME"]
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "change-me")

dynamodb = boto3.client("dynamodb")
events = boto3.client("events")


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _verify_signature(raw_body: str, supplied: str | None) -> bool:
    if not supplied:
        return False
    expected = hmac.new(
        WEBHOOK_SECRET.encode("utf-8"),
        raw_body.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, supplied)


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    raw_body = event.get("body") or "{}"
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    if not _verify_signature(raw_body, headers.get("x-platform-signature")):
        return _response(401, {"message": "Invalid webhook signature"})

    try:
        payload = json.loads(raw_body)
        project_id = str(payload["project_id"])
        commit_sha = str(payload["commit_sha"])
        environment = str(payload.get("environment", "staging"))
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        return _response(400, {"message": f"Invalid payload: {exc}"})

    event_id = hashlib.sha256(
        f"{project_id}:{commit_sha}:{environment}".encode("utf-8")
    ).hexdigest()
    now = int(time.time())

    try:
        dynamodb.put_item(
            TableName=DDB_TABLE,
            Item={
                "event_id": {"S": event_id},
                "status": {"S": "RECEIVED"},
                "created_at": {"N": str(now)},
                "expires_at": {"N": str(now + 604800)},
            },
            ConditionExpression="attribute_not_exists(event_id)",
        )
    except dynamodb.exceptions.ConditionalCheckFailedException:
        return _response(200, {"message": "Duplicate ignored", "event_id": event_id})

    entry = {
        "Source": "portfolio.gitlab",
        "DetailType": "GitLabDeploymentRequested",
        "Detail": json.dumps({
            "event_id": event_id,
            "project_id": project_id,
            "commit_sha": commit_sha,
            "environment": environment,
        }),
        "EventBusName": EVENT_BUS_NAME,
    }
    result = events.put_events(Entries=[entry])
    if result.get("FailedEntryCount", 0) != 0:
        return _response(502, {"message": "Failed to publish event", "event_id": event_id})

    return _response(202, {"message": "Accepted", "event_id": event_id})
