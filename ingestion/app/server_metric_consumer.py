from __future__ import annotations

import logging
import os
import signal

import psycopg
from kafka import KafkaConsumer
from prometheus_client import Counter, Gauge, start_http_server

from app.common import json_deserializer
from app.config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS


LOG = logging.getLogger("server-metric-consumer")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
TOPIC = os.getenv("SERVER_METRICS_TOPIC", "server.metrics")
METRICS_PORT = int(os.getenv("METRICS_PORT", "8000"))
STOP = False

UP = Gauge("ardmatrix_server_metric_consumer_up", "Whether the metric consumer is running")
PROCESSED = Counter("ardmatrix_server_metrics_processed_total", "Server metrics stored in TimescaleDB")
REJECTED = Counter("ardmatrix_server_metrics_rejected_total", "Server metrics rejected")


def stop_service(*_: object) -> None:
    global STOP
    STOP = True


def store(connection: psycopg.Connection[object], event: dict[str, object]) -> None:
    # Source-agnostic normalized envelopes are handled by
    # infrastructure_metric_consumer. This consumer retains compatibility with
    # the original rich server-metric publisher schema.
    if "metrics" not in event:
        return
    metrics = event["metrics"]
    assert isinstance(metrics, dict)
    connection.execute(
        """
        INSERT INTO telemetry.server_metrics
            (observed_at,server_id,server_key,cpu_utilization_percent,memory_used_bytes,
             memory_utilization_percent,disk_used_bytes,disk_utilization_percent,load_1m,
             storage_free_bytes,disk_read_iops,disk_write_iops,disk_latency_ms,
             network_receive_bps,network_transmit_bps,bandwidth_utilization_percent,
             network_latency_ms,packet_loss_percent,temperature_celsius,humidity_percent,
             airflow_cfm,pue,power_consumption_watts,uptime_seconds,uptime_percent,
             error_rate_per_minute,available,source,is_simulated,event_id)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (observed_at,event_id) DO NOTHING
        """,
        (event["observed_at"],event["server_id"],event["server_key"],
         metrics["cpu_utilization_percent"],metrics["memory_used_bytes"],
         metrics["memory_utilization_percent"],metrics["disk_used_bytes"],
         metrics["disk_utilization_percent"],metrics["load_1m"],metrics["storage_free_bytes"],
         metrics["disk_read_iops"],metrics["disk_write_iops"],metrics["disk_latency_ms"],
         metrics["network_receive_bps"],metrics["network_transmit_bps"],
         metrics["bandwidth_utilization_percent"],metrics["network_latency_ms"],
         metrics["packet_loss_percent"],metrics["temperature_celsius"],metrics["humidity_percent"],
         metrics["airflow_cfm"],metrics["pue"],metrics["power_consumption_watts"],
         metrics["uptime_seconds"],metrics["uptime_percent"],metrics["error_rate_per_minute"],
         metrics["available"],event["source"],
         event["is_simulated"],event["event_id"]),
    )
    connection.commit()


def main() -> None:
    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    start_http_server(METRICS_PORT)
    connection = psycopg.connect(DATABASE_URL)
    consumer = KafkaConsumer(
        TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id="server-metrics-timescale-v1",
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        value_deserializer=json_deserializer,
    )
    UP.set(1)
    try:
        while not STOP:
            for messages in consumer.poll(timeout_ms=1000, max_records=500).values():
                for message in messages:
                    try:
                        store(connection, message.value)
                        PROCESSED.inc()
                    except Exception:
                        connection.rollback()
                        REJECTED.inc()
                        LOG.exception("rejected server metric")
                    consumer.commit()
    finally:
        UP.set(0)
        consumer.close()
        connection.close()


if __name__ == "__main__":
    main()
