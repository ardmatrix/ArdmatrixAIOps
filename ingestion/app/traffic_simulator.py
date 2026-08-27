from __future__ import annotations

import json
import logging
import os
import random
import signal
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime, timedelta
from typing import Any

import psycopg
from prometheus_client import Counter, Gauge, start_http_server

from .config import DATABASE_URL

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("kafka-traffic-simulator")

BASE_URL = os.getenv("SOURCE_INGESTION_URL", "http://source-ingestion-api:8000").rstrip("/")
API_TOKEN = os.getenv("SOURCE_API_TOKEN", "demo-local-token")
RUN_KEY = os.getenv("SIMULATOR_RUN_KEY", "customer-demo-10d-v1")
INTERVAL = int(os.getenv("SIMULATOR_INTERVAL_SECONDS", "900"))
DURATION_DAYS = int(os.getenv("SIMULATOR_DURATION_DAYS", "10"))
METRICS_PORT = int(os.getenv("SIMULATOR_METRICS_PORT", "8000"))
SITES = ("dc-chicago", "dc-london", "dc-singapore", "dc-mumbai")

EVENTS = Counter("kafka_simulator_events_total", "Simulator events", ["source_type", "result"])
BATCHES = Counter("kafka_simulator_batches_total", "Simulator batches", ["result"])
RUNNING = Gauge("kafka_simulator_running", "Whether the timed simulation is active")
REMAINING = Gauge("kafka_simulator_remaining_seconds", "Seconds remaining in the simulation")
LAST_BATCH = Gauge("kafka_simulator_last_batch_timestamp_seconds", "Last successful batch time")
STOP = False


def stop(*_: object) -> None:
    global STOP
    STOP = True


def post(path: str, payload: dict[str, Any]) -> None:
    request = urllib.request.Request(
        f"{BASE_URL}/ingest/{path}",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {API_TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status != 202:
            raise RuntimeError(f"ingestion API returned HTTP {response.status}")


def events_for(batch: int) -> list[tuple[str, dict[str, Any]]]:
    rng = random.Random(f"{RUN_KEY}:{batch}")
    observed_at = datetime.now(UTC).isoformat()
    phase = (batch - 1) % 96
    scenario_day = (batch - 1) // 96 + 1
    incident_key = f"SIM-MEMLEAK-D{scenario_day:02d}"
    events: list[tuple[str, dict[str, Any]]] = []
    for site_index, site in enumerate(SITES, 1):
        for server_index in (1, 2):
            server_asset = f"{site}-rack-01-srv-{server_index:02d}"
            network_degraded = site == "dc-singapore" and server_index == 1 and 44 <= phase <= 56
            memory_value = round(rng.uniform(35, 68), 1)
            if site == "dc-chicago" and server_index == 1 and 16 <= phase <= 36:
                memory_value = min(96.0, round(48 + (phase - 16) * 2.35, 1))
            events.append(("telemetry", {
                "source_system": f"{site}-node-exporter", "site_id": site,
                "asset_id": server_asset, "event_type": "server.performance",
                "observed_at": observed_at, "is_simulated": True,
                "payload": {"cpu_utilization_percent": round(rng.uniform(22, 88), 1),
                            "memory_utilization_percent": memory_value,
                            "disk_utilization_percent": round(rng.uniform(28, 82), 1),
                            "temperature_celsius": round(rng.uniform(24, 43), 1),
                            "network_latency_ms": round(rng.uniform(95, 180), 1) if network_degraded else round(rng.uniform(4, 18), 1),
                            "packet_loss_percent": round(rng.uniform(3.5, 8.5), 2) if network_degraded else round(rng.uniform(0, 0.25), 2),
                            "bandwidth_utilization_percent": round(rng.uniform(72, 94), 1) if network_degraded else round(rng.uniform(18, 68), 1)},
            }))
            for vm_index in (1, 2, 3):
                vm_asset = f"{server_asset}-vm-{vm_index}"
                events.append(("telemetry", {
                    "source_system": f"{site}-vmware-collector", "topic": "vm.metrics",
                    "site_id": site, "asset_id": vm_asset, "event_type": "vm.performance",
                    "observed_at": observed_at, "is_simulated": True,
                    "payload": {"physical_server_id": server_asset,
                                "cpu_utilization_percent": round(rng.uniform(12, 82), 1),
                                "memory_utilization_percent": round(rng.uniform(28, 88), 1),
                                "storage_utilization_percent": round(rng.uniform(25, 79), 1),
                                "uptime_percent": 99.99, "available": True},
                }))
        port_down = batch % 32 == site_index
        network_incident = site == "dc-singapore" and 44 <= phase <= 56
        events.append(("snmp", {
            "source_system": f"{site}-snmp-poller", "site_id": site,
            "asset_id": f"{site}-access-01", "event_type": "interface.telemetry",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"interface": "Gi1/0/24", "admin_status": "up",
                        "oper_status": "down" if port_down else "up",
                        "rx_utilization_percent": round(rng.uniform(75, 96), 1) if network_incident else round(rng.uniform(8, 70), 1),
                        "tx_utilization_percent": round(rng.uniform(75, 96), 1) if network_incident else round(rng.uniform(8, 70), 1),
                        "errors": rng.randint(40, 120) if network_incident else (rng.randint(1, 12) if port_down else rng.randint(0, 2)),
                        "network_latency_ms": round(rng.uniform(95, 180), 1) if network_incident else round(rng.uniform(3, 16), 1),
                        "packet_loss_percent": round(rng.uniform(3.5, 8.5), 2) if network_incident else round(rng.uniform(0, 0.2), 2)},
        }))
        events.append(("telemetry", {
            "source_system": f"{site}-kube-state-metrics", "topic": "kubernetes.metrics",
            "site_id": site, "asset_id": f"{site}-cluster-01", "event_type": "kubernetes.cluster",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"ready_nodes": 6, "running_pods": 18, "failed_pods": 1 if port_down else 0,
                        "pod_restarts": rng.randint(0, 4)},
        }))
        events.append(("api", {
            "source_system": f"{site}-billing-api", "site_id": site,
            "asset_id": f"{site}-billing-service", "event_type": "application.performance",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"availability_percent": 99.1 if port_down else 99.99,
                        "latency_ms": rng.randint(450, 900) if port_down else rng.randint(45, 180),
                        "requests_per_minute": rng.randint(800, 2400),
                        "error_rate_percent": round(rng.uniform(2, 6), 2) if port_down else round(rng.uniform(0, .8), 2)},
        }))
        events.append(("logs", {
            "source_system": f"{site}-fluent-bit", "topic": "logs.application",
            "site_id": site, "asset_id": f"{site}-billing-api-pod-01", "event_type": "application.log",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"severity": "ERROR" if port_down else "INFO",
                        "message": "Upstream network timeout" if port_down else "Health check completed",
                        "batch": batch},
        }))
    scenario_asset = "dc-chicago-rack-01-srv-01"
    if phase == 24:
        events.append(("api", {
            "source_system": "ardmatrix-anomaly-engine", "topic": "anomalies.events",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "anomaly.detected",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"metric_name": "memory_utilization_percent", "actual_value": 66.8,
                        "baseline_value": 49.5, "anomaly_score": 0.87, "severity": "warning",
                        "model_name": "IsolationForest-demo", "scenario": "progressive-memory-leak"},
        }))
    if phase == 26:
        events.append(("api", {
            "source_system": "ardmatrix-forecast-engine", "topic": "ai.findings",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "forecast.prediction",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"metric_name": "memory_utilization_percent", "horizon_hours": 24,
                        "predicted_value": 94.2, "threshold_value": 85.0,
                        "predicted_breach_at": (datetime.now(UTC) + timedelta(hours=6)).isoformat(),
                        "confidence": 0.91, "model_name": "linear-trend-demo"},
        }))
    if phase == 28:
        events.append(("api", {
            "source_system": "ardmatrix-alert-engine", "topic": "alerts.events",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "alert.opened",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": incident_key, "severity": "critical",
                        "metric_name": "memory_utilization_percent", "actual_value": 86.7,
                        "threshold_value": 85.0, "message": "Sustained memory threshold breach"},
        }))
    if phase == 29:
        events.append(("api", {
            "source_system": "ardmatrix-correlation-engine", "topic": "ai.findings",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "incident.correlated",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": incident_key, "severity": "critical", "status": "open",
                        "root_asset_id": scenario_asset, "correlated_event_count": 7,
                        "impacted_services": ["Billing API", "Customer Portal"],
                        "summary": "Memory leak correlated with pod restarts, API latency and error-rate increase",
                        "correlation_confidence": 0.93},
        }))
    if phase == 30:
        events.append(("api", {
            "source_system": "ardmatrix-rca-engine", "topic": "rca.events",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "rca.completed",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": incident_key, "root_asset_id": scenario_asset,
                        "probable_cause": "Memory leak in billing-api worker after application deployment",
                        "confidence": 0.89, "service_impact": "Billing API latency and Customer Portal errors",
                        "evidence": ["memory slope +2.35% per interval", "pod restart increase",
                                     "API latency correlated at 0.91", "deployment preceded deviation"],
                        "recommendation": "Rollback the billing-api deployment and restart the affected worker"},
        }))
    if phase == 36:
        events.append(("api", {
            "source_system": "ardmatrix-correlation-engine", "topic": "ai.findings",
            "site_id": "dc-chicago", "asset_id": scenario_asset, "event_type": "incident.correlated",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": incident_key, "severity": "info", "status": "resolved",
                        "root_asset_id": scenario_asset, "correlated_event_count": 8,
                        "impacted_services": ["Billing API", "Customer Portal"],
                        "summary": "Metrics returned to baseline after remediation",
                        "correlation_confidence": 0.96},
        }))
    network_asset = "dc-singapore-access-01"
    network_server = "dc-singapore-rack-01-srv-01"
    network_incident_key = f"SIM-NETWORK-D{scenario_day:02d}"
    if phase == 48:
        events.append(("api", {
            "source_system": "ardmatrix-anomaly-engine", "topic": "anomalies.events",
            "site_id": "dc-singapore", "asset_id": network_server, "event_type": "anomaly.detected",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"metric_name": "packet_loss_percent", "actual_value": 5.8,
                        "baseline_value": 0.12, "anomaly_score": 0.96, "severity": "critical",
                        "model_name": "IsolationForest-demo", "related_asset": network_asset,
                        "network_latency_ms": 142.0, "scenario": "network-degradation"},
        }))
    if phase == 49:
        events.append(("api", {
            "source_system": "ardmatrix-forecast-engine", "topic": "ai.findings",
            "site_id": "dc-singapore", "asset_id": network_server, "event_type": "forecast.prediction",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"metric_name": "packet_loss_percent", "horizon_hours": 6,
                        "predicted_value": 9.2, "threshold_value": 3.0,
                        "predicted_breach_at": (datetime.now(UTC) + timedelta(hours=1)).isoformat(),
                        "confidence": 0.94, "model_name": "network-trend-demo"},
        }))
    if phase == 50:
        events.append(("api", {
            "source_system": "ardmatrix-correlation-engine", "topic": "ai.findings",
            "site_id": "dc-singapore", "asset_id": network_server, "event_type": "incident.correlated",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": network_incident_key, "severity": "critical", "status": "open",
                        "root_asset_id": network_asset, "correlated_event_count": 11,
                        "impacted_services": ["Billing API", "Kubernetes Cluster", "Customer Portal"],
                        "summary": "Packet loss and latency correlated with pod failures and API degradation",
                        "correlation_confidence": 0.95},
        }))
    if phase == 51:
        events.append(("api", {
            "source_system": "ardmatrix-rca-engine", "topic": "rca.events",
            "site_id": "dc-singapore", "asset_id": network_server, "event_type": "rca.completed",
            "observed_at": observed_at, "is_simulated": True,
            "payload": {"incident_key": network_incident_key, "root_asset_id": network_asset,
                        "probable_cause": "CRC errors on access-switch interface Gi1/0/24 caused packet loss and latency",
                        "confidence": 0.92, "service_impact": "Kubernetes pod failures and Billing API latency",
                        "evidence": ["packet loss increased from 0.12% to 5.8%", "latency increased to 142 ms",
                                     "interface errors exceeded baseline", "dependent server shares Gi1/0/24"],
                        "recommendation": "Inspect cable/transceiver on Gi1/0/24 and fail traffic to the redundant path"},
        }))
    return events


def ensure_run() -> tuple[datetime, datetime, int, datetime | None]:
    now = datetime.now(UTC)
    with psycopg.connect(DATABASE_URL) as connection:
        connection.execute(
            """INSERT INTO ingestion.simulator_runs
               (run_key,started_at,ends_at,interval_seconds,status)
               VALUES (%s,%s,%s,%s,'running') ON CONFLICT (run_key) DO NOTHING""",
            (RUN_KEY, now, now + timedelta(days=DURATION_DAYS), INTERVAL),
        )
        row = connection.execute(
            "SELECT started_at,ends_at,batch_count,last_emitted_at FROM ingestion.simulator_runs WHERE run_key=%s",
            (RUN_KEY,),
        ).fetchone()
    return row[0], row[1], row[2], row[3]


def update_run(batch_events: int, failed: int) -> None:
    with psycopg.connect(DATABASE_URL) as connection:
        connection.execute(
            """UPDATE ingestion.simulator_runs SET last_emitted_at=now(),batch_count=batch_count+1,
               event_count=event_count+%s,error_count=error_count+%s,updated_at=now() WHERE run_key=%s""",
            (batch_events - failed, failed, RUN_KEY),
        )


def complete_run() -> None:
    with psycopg.connect(DATABASE_URL) as connection:
        connection.execute("UPDATE ingestion.simulator_runs SET status='completed',updated_at=now() WHERE run_key=%s", (RUN_KEY,))


def main() -> None:
    if INTERVAL < 10 or DURATION_DAYS < 1:
        raise ValueError("simulator interval must be >=10 seconds and duration >=1 day")
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    start_http_server(METRICS_PORT)
    LOG.info("simulation %s: every %ss for %s days", RUN_KEY, INTERVAL, DURATION_DAYS)
    while not STOP:
        _, ends_at, batch, last_at = ensure_run()
        now = datetime.now(UTC)
        remaining = max(0, (ends_at - now).total_seconds())
        REMAINING.set(remaining)
        if remaining <= 0:
            RUNNING.set(0)
            complete_run()
            time.sleep(60)
            continue
        RUNNING.set(1)
        due = last_at is None or (now - last_at).total_seconds() >= INTERVAL
        if not due:
            time.sleep(min(10, max(1, INTERVAL - (now - last_at).total_seconds())))
            continue
        generated = events_for(batch + 1)
        failed = 0
        for source_type, payload in generated:
            try:
                post(source_type, payload)
                EVENTS.labels(source_type, "published").inc()
            except (OSError, urllib.error.HTTPError, RuntimeError):
                failed += 1
                EVENTS.labels(source_type, "failed").inc()
                LOG.exception("failed to publish %s event", source_type)
        update_run(len(generated), failed)
        BATCHES.labels("partial" if failed else "published").inc()
        LAST_BATCH.set_to_current_time()
        LOG.info("batch %s: published=%s failed=%s", batch + 1, len(generated) - failed, failed)
        time.sleep(1)


if __name__ == "__main__":
    main()
