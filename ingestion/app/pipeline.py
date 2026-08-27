from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any
from uuid import UUID, uuid4


ALLOWED_TOPICS = {
    "server.metrics",
    "vm.metrics",
    "network.metrics",
    "kubernetes.metrics",
    "application.metrics",
    "inventory.events",
    "topology.events",
    "alerts.events",
    "anomalies.events",
    "ai.findings",
    "rca.events",
    "logs.system",
    "logs.application",
    "logs.network",
    "logs.security",
    "ingestion.errors",
}

SOURCE_DEFAULT_TOPICS = {
    "api": "application.metrics",
    "telemetry": "server.metrics",
    "snmp": "network.metrics",
    "log": "logs.system",
    "csv": "inventory.events",
    "json": "inventory.events",
}


class ValidationError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def utc_timestamp(value: Any) -> str:
    if value in (None, ""):
        return datetime.now(timezone.utc).isoformat()
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError as error:
        raise ValidationError("INVALID_TIMESTAMP", "observed_at must be ISO-8601") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


def normalize_event(source_type: str, body: dict[str, Any]) -> dict[str, Any]:
    if source_type not in SOURCE_DEFAULT_TOPICS:
        raise ValidationError("INVALID_SOURCE_TYPE", f"unsupported source type: {source_type}")
    if not isinstance(body, dict):
        raise ValidationError("INVALID_PAYLOAD", "request body must be a JSON object")

    source_system = str(body.get("source_system") or "").strip()
    if not source_system:
        raise ValidationError("MISSING_SOURCE_SYSTEM", "source_system is required")

    topic = str(body.get("topic") or SOURCE_DEFAULT_TOPICS[source_type]).strip()
    if topic not in ALLOWED_TOPICS:
        raise ValidationError("TOPIC_NOT_ALLOWED", f"topic is not allow-listed: {topic}")

    event_type = str(body.get("event_type") or f"{source_type}.event").strip()
    payload = body.get("payload", body.get("data", {}))
    if not isinstance(payload, dict):
        raise ValidationError("INVALID_PAYLOAD", "payload must be a JSON object")

    supplied_id = body.get("message_id")
    try:
        message_id = str(UUID(str(supplied_id))) if supplied_id else str(uuid4())
    except ValueError as error:
        raise ValidationError("INVALID_MESSAGE_ID", "message_id must be a UUID") from error

    return {
        "schema_version": "1.0",
        "message_id": message_id,
        "source_type": source_type,
        "source_system": source_system,
        "topic": topic,
        "event_type": event_type,
        "asset_id": _optional_text(body.get("asset_id")),
        "site_id": _optional_text(body.get("site_id")),
        "observed_at": utc_timestamp(body.get("observed_at")),
        "received_at": datetime.now(timezone.utc).isoformat(),
        "is_simulated": bool(body.get("is_simulated", False)),
        "labels": body.get("labels") if isinstance(body.get("labels"), dict) else {},
        "payload": payload,
    }


def encode_payload(event: dict[str, Any]) -> str:
    return json.dumps(event["payload"], separators=(",", ":"), default=str)


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    result = str(value).strip()
    return result or None
