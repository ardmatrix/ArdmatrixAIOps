from __future__ import annotations

import csv
import json
import os
import shutil
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from uuid import uuid4

import psycopg
from psycopg import sql

from app.config import DATABASE_URL


EXPORT_ROOT = Path(os.getenv("EXPORT_ROOT", "/exports/inventory"))
EXPORT_PORT = int(os.getenv("EXPORT_PORT", "8000"))


def csv_value(value: Any) -> Any:
    if isinstance(value, (dict, list, tuple)):
        return json.dumps(value, default=str, sort_keys=True)
    return value


def create_export() -> tuple[Path, Path, int, int]:
    export_name = f"inventory-{datetime.now(UTC):%Y%m%dT%H%M%SZ}-{uuid4().hex[:6]}"
    export_dir = EXPORT_ROOT / export_name
    export_dir.mkdir(parents=True, exist_ok=False)
    total_rows = 0
    table_count = 0

    with psycopg.connect(DATABASE_URL) as connection:
        tables = connection.execute(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'inventory' AND table_type = 'BASE TABLE'
            ORDER BY table_name
            """
        ).fetchall()

        manifest_rows: list[tuple[str, int]] = []
        for (table_name,) in tables:
            with connection.cursor() as cursor:
                cursor.execute(
                    sql.SQL("SELECT * FROM inventory.{} ORDER BY 1").format(
                        sql.Identifier(table_name)
                    )
                )
                rows = cursor.fetchall()
                columns = [column.name for column in cursor.description or ()]

            output = export_dir / f"{table_name}.csv"
            with output.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(columns)
                writer.writerows([[csv_value(value) for value in row] for row in rows])

            row_count = len(rows)
            manifest_rows.append((table_name, row_count))
            total_rows += row_count
            table_count += 1

    with (export_dir / "manifest.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["table", "row_count"])
        writer.writerows(manifest_rows)
        writer.writerow(["TOTAL", total_rows])

    zip_path = Path(shutil.make_archive(str(export_dir), "zip", export_dir))
    return export_dir, zip_path, table_count, total_rows


class ExportHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return

        if self.path.rstrip("/") != "/export":
            self.send_error(404, "Use /export to download all inventory")
            return

        try:
            export_dir, zip_path, table_count, total_rows = create_export()
            payload = zip_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", f'attachment; filename="{zip_path.name}"')
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("X-Inventory-Export-Folder", export_dir.name)
            self.send_header("X-Inventory-Table-Count", str(table_count))
            self.send_header("X-Inventory-Row-Count", str(total_rows))
            self.end_headers()
            self.wfile.write(payload)
        except Exception as error:
            self.send_error(500, f"Inventory export failed: {error}")

    def log_message(self, message_format: str, *args: Any) -> None:
        print(f"inventory-exporter: {message_format % args}", flush=True)


def main() -> None:
    EXPORT_ROOT.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", EXPORT_PORT), ExportHandler)
    print(f"inventory-exporter listening on port {EXPORT_PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
