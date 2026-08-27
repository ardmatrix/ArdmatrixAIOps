from __future__ import annotations

import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import psycopg
from kafka import KafkaProducer
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest

from .common import json_serializer
from .config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS
from .pipeline import ValidationError, encode_payload, normalize_event

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("source-ingestion-api")

PORT = int(os.getenv("SOURCE_INGESTION_PORT", "8000"))
API_TOKEN = os.getenv("SOURCE_API_TOKEN", "demo-local-token")
SOURCE_PATHS = {"/ingest/api": "api", "/ingest/telemetry": "telemetry", "/ingest/snmp": "snmp", "/ingest/logs": "log"}

EVENTS = Counter("source_ingestion_events_total", "Source events handled", ["source_type", "topic", "result"])
LAST_SUCCESS = Gauge("source_ingestion_last_success_timestamp_seconds", "Last publish time", ["source_type"])


def audit(event: dict[str, Any], status: str, error_code: str | None = None, error_message: str | None = None) -> None:
    with psycopg.connect(DATABASE_URL) as connection:
        connection.execute(
            """
            INSERT INTO ingestion.source_events
                (message_id, source_type, source_system, topic, event_type, asset_id,
                 site_id, status, is_simulated, observed_at, published_at,
                 error_code, error_message, payload)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                    CASE WHEN %s='published' THEN now() END,%s,%s,%s::jsonb)
            ON CONFLICT (message_id) DO NOTHING
            """,
            (event["message_id"], event["source_type"], event["source_system"], event["topic"],
             event["event_type"], event["asset_id"], event["site_id"], status,
             event["is_simulated"], event["observed_at"], status, error_code,
             error_message, encode_payload(event)),
        )


def reject(producer: KafkaProducer, source_type: str, body: Any, error_code: str, error_message: str) -> None:
    raw = body if isinstance(body, dict) else {"raw_type": type(body).__name__}
    event = normalize_event("json", {
        "source_system": str(raw.get("source_system") or f"unknown-{source_type}"),
        "topic": "ingestion.errors",
        "event_type": "ingestion.event_rejected",
        "asset_id": raw.get("asset_id"),
        "site_id": raw.get("site_id"),
        "payload": {"requested_source_type": source_type, "error_code": error_code,
                    "error_message": error_message, "input": raw},
    })
    event["source_type"] = source_type
    producer.send("ingestion.errors", key=event["message_id"].encode(), value=event).get(timeout=15)
    audit(event, "rejected", error_code, error_message)


class Handler(BaseHTTPRequestHandler):
    producer: KafkaProducer

    def send_json(self, code: int, value: Any) -> None:
        payload = json.dumps(value, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_json(200, {"status": "healthy", "service": "source-ingestion-api"})
        elif self.path == "/metrics":
            payload = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        elif self.path == "/":
            self.send_json(200, {"service": "ARDMATRIX source ingestion", "endpoints": list(SOURCE_PATHS)})
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        source_type = SOURCE_PATHS.get(self.path.rstrip("/"))
        if source_type is None:
            self.send_error(404)
            return
        if self.headers.get("Authorization") != f"Bearer {API_TOKEN}":
            self.send_json(401, {"error": "UNAUTHORIZED"})
            return
        body: Any = {}
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 1_048_576:
                raise ValidationError("INVALID_SIZE", "body must be between 1 byte and 1 MiB")
            body = json.loads(self.rfile.read(length))
            event = normalize_event(source_type, body)
            self.producer.send(event["topic"], key=(event["asset_id"] or event["message_id"]).encode(), value=event).get(timeout=15)
            audit(event, "published")
            EVENTS.labels(source_type, event["topic"], "published").inc()
            LAST_SUCCESS.labels(source_type).set_to_current_time()
            self.send_json(202, {"status": "published", "message_id": event["message_id"], "topic": event["topic"]})
        except ValidationError as error:
            reject(self.producer, source_type, body, error.code, str(error))
            EVENTS.labels(source_type, "ingestion.errors", "rejected").inc()
            self.send_json(400, {"error": error.code, "message": str(error)})
        except (json.JSONDecodeError, UnicodeDecodeError):
            reject(self.producer, source_type, body, "INVALID_JSON", "request body is not valid JSON")
            EVENTS.labels(source_type, "ingestion.errors", "rejected").inc()
            self.send_json(400, {"error": "INVALID_JSON"})
        except Exception as error:
            LOG.exception("ingestion failed")
            self.send_json(503, {"error": "INGESTION_UNAVAILABLE", "message": str(error)})

    def log_message(self, message_format: str, *args: Any) -> None:
        LOG.info(message_format, *args)


def main() -> None:
    Handler.producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=json_serializer,
        acks="all",
        retries=10,
    )
    LOG.info("source ingestion API listening on %s", PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
