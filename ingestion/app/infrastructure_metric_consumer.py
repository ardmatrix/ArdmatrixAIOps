from __future__ import annotations

import logging

import psycopg
from kafka import KafkaConsumer
from prometheus_client import Counter, Gauge, start_http_server

from .common import json_deserializer
from .config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS, METRICS_PORT

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("infrastructure-metric-consumer")

PROCESSED = Counter("infrastructure_metrics_processed_total", "Normalized infrastructure metrics", ["asset_type", "result"])
UP = Gauge("infrastructure_metric_consumer_up", "Whether the consumer is running")


def store_server(connection: psycopg.Connection, event: dict) -> None:
    payload = event.get("payload") or {}
    server = connection.execute("SELECT id,server_key FROM inventory.servers WHERE server_key=%s", (event.get("asset_id"),)).fetchone()
    if server is None:
        raise ValueError(f"unknown server asset_id: {event.get('asset_id')}")
    connection.execute(
        """INSERT INTO telemetry.server_metrics
           (observed_at,server_id,server_key,cpu_utilization_percent,memory_used_bytes,
            memory_utilization_percent,disk_used_bytes,disk_utilization_percent,load_1m,
            network_receive_bps,network_transmit_bps,uptime_seconds,temperature_celsius,
            network_latency_ms,packet_loss_percent,bandwidth_utilization_percent,
            available,source,is_simulated,event_id)
           VALUES (%s,%s,%s,%s,0,%s,0,%s,0,0,0,0,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""",
        (event["observed_at"], server[0], server[1], payload.get("cpu_utilization_percent"),
         payload.get("memory_utilization_percent"), payload.get("disk_utilization_percent"),
         payload.get("temperature_celsius"), payload.get("network_latency_ms", 0),
         payload.get("packet_loss_percent", 0), payload.get("bandwidth_utilization_percent", 0),
         payload.get("available", True),
         event.get("source_system", "normalized-ingestion"), event.get("is_simulated", False), event["message_id"]),
    )


def store_vm(connection: psycopg.Connection, event: dict) -> None:
    payload = event.get("payload") or {}
    vm = connection.execute("SELECT id,vm_key FROM inventory.virtual_machines WHERE vm_key=%s", (event.get("asset_id"),)).fetchone()
    if vm is None:
        raise ValueError(f"unknown VM asset_id: {event.get('asset_id')}")
    available = bool(payload.get("available", True))
    connection.execute(
        """INSERT INTO telemetry.vm_metrics
           (observed_at,vm_id,vm_key,cpu_utilization_percent,memory_utilization_percent,
            storage_utilization_percent,uptime_percent,available,source,is_simulated,event_id)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""",
        (event["observed_at"], vm[0], vm[1], payload.get("cpu_utilization_percent"),
         payload.get("memory_utilization_percent"), payload.get("storage_utilization_percent"),
         payload.get("uptime_percent", 99.99), available, event.get("source_system", "normalized-ingestion"),
         event.get("is_simulated", False), event["message_id"]),
    )
    connection.execute(
        """UPDATE inventory.virtual_machines SET cpu_utilization_pct=%s,
             memory_utilization_pct=%s,storage_utilization_pct=%s,uptime_pct=%s,
             status=%s,health_status=%s,last_seen_at=%s,updated_at=now()
           WHERE id=%s""",
        (payload.get("cpu_utilization_percent"), payload.get("memory_utilization_percent"),
         payload.get("storage_utilization_percent"), payload.get("uptime_percent", 99.99),
         "running" if available else "stopped", "healthy" if available else "critical",
         event["observed_at"], vm[0]),
    )


def main() -> None:
    start_http_server(METRICS_PORT)
    consumer = KafkaConsumer(
        "server.metrics", "vm.metrics", bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id="ardmatrix-normalized-infrastructure-store-v2", auto_offset_reset="latest",
        enable_auto_commit=False, value_deserializer=json_deserializer,
    )
    UP.set(1)
    for message in consumer:
        event = message.value or {}
        if "payload" not in event:
            consumer.commit()
            continue
        asset_type = "vm" if message.topic == "vm.metrics" else "server"
        try:
            with psycopg.connect(DATABASE_URL) as connection:
                (store_vm if asset_type == "vm" else store_server)(connection, event)
            PROCESSED.labels(asset_type, "stored").inc()
        except Exception:
            PROCESSED.labels(asset_type, "rejected").inc()
            LOG.exception("rejected %s metric at offset %s", asset_type, message.offset)
        consumer.commit()


if __name__ == "__main__":
    main()
