from __future__ import annotations

import logging
import math
import os
import signal
import time
from datetime import UTC, datetime
from hashlib import sha256
from uuid import uuid4

import psycopg
from kafka import KafkaProducer
from prometheus_client import Gauge, start_http_server

from app.common import json_serializer
from app.config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS


LOG = logging.getLogger("server-metric-publisher")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
TOPIC = os.getenv("SERVER_METRICS_TOPIC", "server.metrics")
INTERVAL = float(os.getenv("SERVER_METRICS_INTERVAL", "15"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "8000"))
STOP = False

UP = Gauge("ardmatrix_server_metric_publisher_up", "Whether the metric publisher is running")
CPU = Gauge("ardmatrix_server_cpu_utilization_percent", "Current simulated CPU utilization", ["server_key", "site_key"])
MEMORY = Gauge("ardmatrix_server_memory_utilization_percent", "Current simulated memory utilization", ["server_key", "site_key"])
DISK = Gauge("ardmatrix_server_disk_utilization_percent", "Current simulated disk utilization", ["server_key", "site_key"])
STORAGE_FREE = Gauge("ardmatrix_server_storage_free_bytes", "Current simulated free storage", ["server_key", "site_key"])
DISK_LATENCY = Gauge("ardmatrix_server_disk_latency_ms", "Current simulated disk latency", ["server_key", "site_key"])
NETWORK_LATENCY = Gauge("ardmatrix_server_network_latency_ms", "Current simulated network latency", ["server_key", "site_key"])
PACKET_LOSS = Gauge("ardmatrix_server_packet_loss_percent", "Current simulated packet loss", ["server_key", "site_key"])
TEMPERATURE = Gauge("ardmatrix_server_temperature_celsius", "Current simulated server inlet temperature", ["server_key", "site_key"])
POWER = Gauge("ardmatrix_server_power_consumption_watts", "Current simulated server power consumption", ["server_key", "site_key"])
AVAILABLE = Gauge("ardmatrix_server_available", "Current simulated server availability", ["server_key", "site_key"])


def stop_service(*_: object) -> None:
    global STOP
    STOP = True


def bounded(value: float, low: float, high: float) -> float:
    return round(max(low, min(high, value)), 2)


def metric_value(server_key: str, phase: float, base: float, amplitude: float) -> float:
    seed = int.from_bytes(sha256(server_key.encode()).digest()[:4], "big")
    return base + amplitude * math.sin(phase + (seed % 360) * math.pi / 180)


def load_servers(connection: psycopg.Connection[object]) -> list[tuple[object, ...]]:
    return connection.execute(
        """
        SELECT sv.id,sv.server_key,s.site_key,coalesce(sc.ram_bytes,0),
               coalesce(sc.local_storage_bytes,0),coalesce(sc.logical_processors,1)
        FROM inventory.servers sv
        JOIN inventory.server_capacity sc ON sc.id=sv.id
        JOIN inventory.racks r ON r.id=sv.rack_id
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id
        JOIN inventory.sites s ON s.id=rm.site_id
        WHERE sv.status='active'
        ORDER BY sv.server_key
        """
    ).fetchall()


def main() -> None:
    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    start_http_server(METRICS_PORT)
    # Server discovery is read-only. Autocommit prevents the long-running
    # publisher loop from holding an idle transaction and blocking TimescaleDB
    # retention jobs and Grafana inventory queries.
    connection = psycopg.connect(DATABASE_URL, autocommit=True)
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        acks="all",
        value_serializer=json_serializer,
    )
    started_at = time.time()
    UP.set(1)
    try:
        while not STOP:
            observed_at = datetime.now(UTC).replace(microsecond=0)
            phase = observed_at.timestamp() / 120
            for server_id, server_key, site_key, ram_bytes, storage_bytes, processors in load_servers(connection):
                cpu = bounded(metric_value(server_key, phase, 42, 25), 2, 95)
                memory = bounded(metric_value(server_key, phase / 2, 58, 18), 10, 96)
                disk = bounded(metric_value(server_key, phase / 12, 52, 12), 5, 94)
                read_iops = bounded(metric_value(server_key, phase / 3, 620, 360), 20, 1600)
                write_iops = bounded(metric_value(server_key, phase / 3 + 1.2, 390, 240), 10, 1100)
                disk_latency = bounded(1.2 + (read_iops + write_iops) / 650, 0.4, 18)
                bandwidth = bounded((cpu * 0.55) + metric_value(server_key, phase / 4, 15, 8), 2, 92)
                network_latency = bounded(metric_value(server_key, phase / 5, 8, 4), 1, 35)
                packet_loss = bounded(max(0, (network_latency - 10) * 0.025), 0, 2.5)
                temperature = bounded(20 + cpu * 0.12 + metric_value(server_key, phase / 8, 0, 1.5), 18, 38)
                humidity = bounded(metric_value(server_key, phase / 10, 46, 7), 30, 65)
                airflow = bounded(180 + cpu * 2.4, 150, 450)
                pue = bounded(metric_value(site_key, phase / 30, 1.42, 0.09), 1.18, 1.8)
                power = bounded(180 + cpu * 6.2 + memory * 1.1, 180, 950)
                uptime_percent = bounded(99.90 + metric_value(server_key, phase / 50, 0.06, 0.03), 99.5, 100)
                error_rate = bounded(max(0, (cpu - 70) * 0.015 + packet_loss * 0.4), 0, 3)
                available = True
                payload = {
                    "event_id": str(uuid4()),
                    "event_type": "server.metric.observed",
                    "observed_at": observed_at.isoformat(),
                    "server_id": str(server_id),
                    "server_key": server_key,
                    "site_key": site_key,
                    "metrics": {
                        "cpu_utilization_percent": cpu,
                        "memory_used_bytes": round(int(ram_bytes) * memory / 100),
                        "memory_utilization_percent": memory,
                        "disk_used_bytes": round(int(storage_bytes) * disk / 100),
                        "disk_utilization_percent": disk,
                        "storage_free_bytes": max(0, round(int(storage_bytes) * (100 - disk) / 100)),
                        "disk_read_iops": read_iops,
                        "disk_write_iops": write_iops,
                        "disk_latency_ms": disk_latency,
                        "load_1m": round(cpu / 100 * int(processors), 2),
                        "network_receive_bps": round(8_000_000 + cpu * 900_000),
                        "network_transmit_bps": round(5_000_000 + cpu * 600_000),
                        "bandwidth_utilization_percent": bandwidth,
                        "network_latency_ms": network_latency,
                        "packet_loss_percent": packet_loss,
                        "temperature_celsius": temperature,
                        "humidity_percent": humidity,
                        "airflow_cfm": airflow,
                        "pue": pue,
                        "power_consumption_watts": power,
                        "uptime_seconds": round(time.time() - started_at + 86400),
                        "uptime_percent": uptime_percent,
                        "error_rate_per_minute": error_rate,
                        "available": available,
                    },
                    "source": "ardmatrix-demo-simulator",
                    "is_simulated": True,
                }
                producer.send(TOPIC, key=server_key.encode(), value=payload)
                CPU.labels(server_key, site_key).set(cpu)
                MEMORY.labels(server_key, site_key).set(memory)
                DISK.labels(server_key, site_key).set(disk)
                STORAGE_FREE.labels(server_key, site_key).set(payload["metrics"]["storage_free_bytes"])
                DISK_LATENCY.labels(server_key, site_key).set(disk_latency)
                NETWORK_LATENCY.labels(server_key, site_key).set(network_latency)
                PACKET_LOSS.labels(server_key, site_key).set(packet_loss)
                TEMPERATURE.labels(server_key, site_key).set(temperature)
                POWER.labels(server_key, site_key).set(power)
                AVAILABLE.labels(server_key, site_key).set(1 if available else 0)
            producer.flush(timeout=10)
            time.sleep(INTERVAL)
    finally:
        UP.set(0)
        producer.close()
        connection.close()


if __name__ == "__main__":
    main()
