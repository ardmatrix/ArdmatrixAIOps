from __future__ import annotations

import os
from pathlib import Path

KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:19092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "inventory.events")
DATABASE_URL = os.environ["DATABASE_URL"]

LANDING_ROOT = Path(os.getenv("LANDING_ROOT", "/landing/inventory"))
INCOMING_DIR = LANDING_ROOT / "incoming"
PROCESSING_DIR = LANDING_ROOT / "processing"
ARCHIVE_DIR = LANDING_ROOT / "archive"
ERRORS_DIR = LANDING_ROOT / "errors"
TEMPLATES_DIR = LANDING_ROOT / "templates"

POLL_SECONDS = float(os.getenv("POLL_SECONDS", "3"))
STABLE_SCANS = int(os.getenv("STABLE_SCANS", "2"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "8000"))

SUPPORTED_ENTITY_TYPES = (
    "owners",
    "sites",
    "rooms",
    "rows",
    "racks",
    "servers",
    "server_cpus",
    "server_memory",
    "server_gpus",
    "server_storage",
    "network_devices",
    "network_interfaces",
    "hypervisors",
    "virtual_machines",
)

LOAD_PRIORITY = {name: index for index, name in enumerate(SUPPORTED_ENTITY_TYPES)}
