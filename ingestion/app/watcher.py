from __future__ import annotations

import csv
import json
import logging
import shutil
import signal
import time
from datetime import UTC, datetime
from pathlib import Path

import psycopg
from kafka import KafkaProducer
from prometheus_client import Counter, Gauge, start_http_server

from .common import json_serializer, sha256_file
from .config import (
    ARCHIVE_DIR,
    DATABASE_URL,
    ERRORS_DIR,
    INCOMING_DIR,
    KAFKA_BOOTSTRAP_SERVERS,
    KAFKA_TOPIC,
    LOAD_PRIORITY,
    METRICS_PORT,
    POLL_SECONDS,
    PROCESSING_DIR,
    STABLE_SCANS,
    SUPPORTED_ENTITY_TYPES,
    TEMPLATES_DIR,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("inventory-watcher")

FILES_RECEIVED = Counter("inventory_files_received_total", "CSV files detected")
FILES_PUBLISHED = Counter("inventory_files_published_total", "CSV files published to Kafka")
FILES_REJECTED = Counter("inventory_files_rejected_total", "CSV files rejected")
FILES_DUPLICATE = Counter("inventory_files_duplicate_total", "Duplicate CSV files ignored")
ROWS_PUBLISHED = Counter("inventory_rows_published_total", "Inventory rows published", ["entity_type"])
WATCHER_UP = Gauge("inventory_watcher_up", "Whether the watcher loop is running")

STOP = False


def stop_service(*_: object) -> None:
    global STOP
    STOP = True


def entity_type_for(path: Path) -> str | None:
    stem = path.stem.lower()
    matches = [name for name in SUPPORTED_ENTITY_TYPES if stem == name or stem.startswith(f"{name}_")]
    return max(matches, key=len) if matches else None


def expected_headers(entity_type: str) -> list[str]:
    with (TEMPLATES_DIR / f"{entity_type}.csv").open(newline="", encoding="utf-8") as handle:
        return next(csv.reader(handle))


def validate_file(path: Path, entity_type: str) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    errors: list[dict[str, object]] = []
    rows: list[dict[str, str]] = []
    expected = expected_headers(entity_type)
    try:
        with path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            actual = reader.fieldnames or []
            missing = [name for name in expected if name not in actual]
            unexpected = [name for name in actual if name not in expected]
            if missing or unexpected:
                errors.append({
                    "row_number": 1,
                    "error_code": "INVALID_HEADERS",
                    "error_message": f"missing={missing}; unexpected={unexpected}",
                })
                return rows, errors
            for number, row in enumerate(reader, 2):
                if None in row or any(value is None for value in row.values()):
                    errors.append({
                        "row_number": number,
                        "error_code": "MALFORMED_ROW",
                        "error_message": "column count does not match header",
                        "row_data": row,
                    })
                    continue
                normalized = {key: value.strip() for key, value in row.items()}
                if not any(normalized.values()):
                    continue
                rows.append(normalized)
    except (UnicodeDecodeError, csv.Error) as exc:
        errors.append({"row_number": None, "error_code": "INVALID_CSV", "error_message": str(exc)})
    if not rows and not errors:
        errors.append({"row_number": None, "error_code": "EMPTY_FILE", "error_message": "CSV has no data rows"})
    return rows, errors


def write_error_report(path: Path, entity_type: str | None, errors: list[dict[str, object]]) -> Path:
    report = ERRORS_DIR / f"{path.name}.errors.json"
    report.write_text(json.dumps({"file": path.name, "entity_type": entity_type, "errors": errors}, indent=2), encoding="utf-8")
    return report


def process_file(path: Path, producer: KafkaProducer) -> None:
    FILES_RECEIVED.inc()
    entity_type = entity_type_for(path)
    checksum = sha256_file(path)
    size = path.stat().st_size
    processing_path = PROCESSING_DIR / path.name
    path.replace(processing_path)

    with psycopg.connect(DATABASE_URL) as connection:
        duplicate = connection.execute(
            "SELECT id FROM ingestion.file_runs WHERE entity_type=%s AND sha256=%s",
            (entity_type or "unsupported", checksum),
        ).fetchone()
        if duplicate:
            destination = ARCHIVE_DIR / f"duplicate-{checksum[:12]}-{processing_path.name}"
            processing_path.replace(destination)
            FILES_DUPLICATE.inc()
            LOG.info("duplicate file archived: %s", destination.name)
            return

        run_id = connection.execute(
            """
            INSERT INTO ingestion.file_runs
                (file_name, entity_type, sha256, file_size_bytes, status, started_at)
            VALUES (%s, %s, %s, %s, 'validating', now()) RETURNING id
            """,
            (processing_path.name, entity_type or "unsupported", checksum, size),
        ).fetchone()[0]

        if entity_type is None:
            errors = [{"row_number": None, "error_code": "UNSUPPORTED_FILE", "error_message": "filename does not match a supported entity type"}]
        else:
            rows, errors = validate_file(processing_path, entity_type)

        if errors:
            report = write_error_report(processing_path, entity_type, errors)
            for error in errors:
                connection.execute(
                    """
                    INSERT INTO ingestion.row_errors
                        (file_run_id, row_number, error_code, error_message, row_data)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (run_id, error.get("row_number"), error["error_code"], error["error_message"],
                     json.dumps(error.get("row_data")) if error.get("row_data") else None),
                )
            connection.execute(
                """
                UPDATE ingestion.file_runs SET status='rejected', rows_rejected=%s,
                    error_summary=%s, completed_at=now(), archive_path=%s WHERE id=%s
                """,
                (len(errors), errors[0]["error_message"], str(report), run_id),
            )
            rejected_path = ERRORS_DIR / processing_path.name
            processing_path.replace(rejected_path)
            FILES_REJECTED.inc()
            LOG.error("rejected %s: %s", rejected_path.name, errors[0]["error_message"])
            return

        connection.execute(
            "UPDATE ingestion.file_runs SET rows_received=%s, rows_published=%s WHERE id=%s",
            (len(rows), len(rows), run_id),
        )
        # Kafka consumers must never observe a file_run_id that is still
        # uncommitted in PostgreSQL.
        connection.commit()

        received_at = datetime.now(UTC).isoformat()
        for index, row in enumerate(rows, 2):
            message_id = f"{checksum}:{index}"
            producer.send(
                KAFKA_TOPIC,
                key=b"inventory-order",
                value={
                    "schema_version": "1.0",
                    "message_id": message_id,
                    "file_run_id": str(run_id),
                    "file_name": processing_path.name,
                    "entity_type": entity_type,
                    "row_number": index,
                    "received_at": received_at,
                    "is_simulated": False,
                    "data": row,
                },
            ).get(timeout=30)
            ROWS_PUBLISHED.labels(entity_type=entity_type).inc()

        archive_name = f"{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}-{processing_path.name}"
        archive_path = ARCHIVE_DIR / archive_name
        processing_path.replace(archive_path)
        connection.execute(
            """
            UPDATE ingestion.file_runs
            SET status = CASE WHEN rows_processed + rows_rejected >= rows_published THEN
                    CASE WHEN rows_rejected > 0 THEN 'rejected' ELSE 'completed' END
                ELSE 'published' END,
                published_at=now(), archive_path=%s,
                completed_at = CASE WHEN rows_processed + rows_rejected >= rows_published
                    THEN now() ELSE completed_at END
            WHERE id=%s
            """,
            (str(archive_path), run_id),
        )
        connection.commit()
        FILES_PUBLISHED.inc()
        LOG.info("published %s rows from %s", len(rows), archive_name)


def main() -> None:
    for directory in (INCOMING_DIR, PROCESSING_DIR, ARCHIVE_DIR, ERRORS_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    start_http_server(METRICS_PORT)
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=json_serializer,
        acks="all",
        retries=10,
    )
    observed: dict[Path, tuple[int, int, int]] = {}
    WATCHER_UP.set(1)
    LOG.info("watching %s for CSV files", INCOMING_DIR)
    try:
        while not STOP:
            candidates = []
            for path in INCOMING_DIR.glob("*.csv"):
                stat = path.stat()
                previous_size, previous_mtime, stable = observed.get(path, (-1, -1, 0))
                stable = stable + 1 if (stat.st_size, stat.st_mtime_ns) == (previous_size, previous_mtime) else 1
                observed[path] = (stat.st_size, stat.st_mtime_ns, stable)
                if stable >= STABLE_SCANS:
                    entity = entity_type_for(path)
                    candidates.append((LOAD_PRIORITY.get(entity or "", 999), path))
            for _, path in sorted(candidates, key=lambda item: (item[0], item[1].name)):
                observed.pop(path, None)
                try:
                    process_file(path, producer)
                except Exception:
                    LOG.exception("failed to process %s", path)
            time.sleep(POLL_SECONDS)
    finally:
        WATCHER_UP.set(0)
        producer.flush(timeout=10)
        producer.close()


if __name__ == "__main__":
    main()
