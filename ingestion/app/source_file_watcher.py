from __future__ import annotations

import csv
import json
import logging
import os
import shutil
import signal
import time
from pathlib import Path
from typing import Any, Iterable

import psycopg
from kafka import KafkaProducer
from prometheus_client import Counter, Gauge, start_http_server

from .common import json_serializer, sha256_file
from .config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS, METRICS_PORT
from .pipeline import ValidationError, encode_payload, normalize_event

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("source-file-watcher")

ROOT = Path(os.getenv("SOURCE_LANDING_ROOT", "/landing"))
POLL_SECONDS = float(os.getenv("SOURCE_FILE_POLL_SECONDS", "3"))
ROUTES = {
    "server": ("telemetry", "server.metrics"),
    "network": ("telemetry", "network.metrics"),
    "kubernetes": ("telemetry", "kubernetes.metrics"),
    "applications": ("api", "application.metrics"),
    "topology": ("api", "topology.events"),
}

FILES = Counter("source_files_total", "Source files handled", ["source", "result"])
ROWS = Counter("source_file_rows_total", "Source file rows handled", ["source", "topic", "result"])
WATCHER_UP = Gauge("source_file_watcher_up", "Whether the source file watcher is running")
STOP = False


def stop(*_: object) -> None:
    global STOP
    STOP = True


def rows_for(path: Path) -> Iterable[dict[str, Any]]:
    if path.suffix.lower() == ".csv":
        with path.open(encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if not reader.fieldnames:
                raise ValidationError("MISSING_HEADERS", "CSV requires a header row")
            for row in reader:
                yield {key: value for key, value in row.items() if key is not None}
        return
    parsed = json.loads(path.read_text(encoding="utf-8"))
    values = parsed if isinstance(parsed, list) else [parsed]
    for value in values:
        if not isinstance(value, dict):
            raise ValidationError("INVALID_JSON_RECORD", "JSON records must be objects")
        yield value


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


def process(path: Path, source: str, producer: KafkaProducer) -> None:
    source_type, topic = ROUTES[source]
    work = path.parent.parent / "processing" / path.name
    archive = path.parent.parent / "archive"
    errors = path.parent.parent / "errors"
    for folder in (work.parent, archive, errors):
        folder.mkdir(parents=True, exist_ok=True)
    path.replace(work)
    checksum = sha256_file(work)
    published = 0
    try:
        for number, row in enumerate(rows_for(work), 1):
            metadata = {
                "source_system": row.pop("source_system", f"{source}-file"),
                "topic": row.pop("topic", topic),
                "event_type": row.pop("event_type", f"{source}.record"),
                "asset_id": row.pop("asset_id", row.get("server_id") or row.get("device_id") or row.get("pod_id")),
                "site_id": row.pop("site_id", None),
                "observed_at": row.pop("observed_at", row.pop("timestamp", None)),
                "is_simulated": str(row.pop("is_simulated", "false")).lower() == "true",
                "payload": row,
            }
            event = normalize_event(source_type, metadata)
            event["message_id"] = _deterministic_id(checksum, number)
            producer.send(event["topic"], key=(event["asset_id"] or event["message_id"]).encode(), value=event).get(timeout=15)
            audit(event, "published")
            ROWS.labels(source, event["topic"], "published").inc()
            published += 1
        if published == 0:
            raise ValidationError("EMPTY_FILE", "file contains no records")
        destination = archive / f"{int(time.time())}-{work.name}"
        work.replace(destination)
        FILES.labels(source, "published").inc()
        LOG.info("published %s records from %s to %s", published, path.name, topic)
    except Exception as error:
        report = errors / f"{work.name}.errors.json"
        report.write_text(json.dumps({"file": work.name, "error": str(error)}, indent=2), encoding="utf-8")
        if work.exists():
            shutil.move(str(work), str(errors / work.name))
        FILES.labels(source, "rejected").inc()
        ROWS.labels(source, "ingestion.errors", "rejected").inc()
        error_event = normalize_event("json", {
            "source_system": f"{source}-file",
            "topic": "ingestion.errors",
            "event_type": "ingestion.file_rejected",
            "payload": {"file": path.name, "error": str(error)},
        })
        producer.send("ingestion.errors", value=error_event).get(timeout=15)
        LOG.error("rejected %s: %s", path.name, error)


def _deterministic_id(checksum: str, row_number: int) -> str:
    # UUID-formatted stable ID provides idempotence across retries.
    value = f"{checksum[:24]}{row_number:08x}"[:32]
    return f"{value[:8]}-{value[8:12]}-{value[12:16]}-{value[16:20]}-{value[20:32]}"


def main() -> None:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    start_http_server(METRICS_PORT)
    producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS, value_serializer=json_serializer, acks="all", retries=10)
    for source in ROUTES:
        for folder in ("incoming", "processing", "archive", "errors"):
            (ROOT / source / folder).mkdir(parents=True, exist_ok=True)
    WATCHER_UP.set(1)
    LOG.info("watching source landing directories under %s", ROOT)
    try:
        while not STOP:
            for source in ROUTES:
                incoming = ROOT / source / "incoming"
                for path in sorted((*incoming.glob("*.csv"), *incoming.glob("*.json"))):
                    try:
                        process(path, source, producer)
                    except Exception:
                        LOG.exception("unexpected failure processing %s", path)
            time.sleep(POLL_SECONDS)
    finally:
        WATCHER_UP.set(0)
        producer.flush(timeout=10)
        producer.close()


if __name__ == "__main__":
    main()
