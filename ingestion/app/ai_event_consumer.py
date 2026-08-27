from __future__ import annotations

import json
import logging
import os

import psycopg
from kafka import KafkaConsumer
from prometheus_client import Counter, Gauge, start_http_server

from .common import json_deserializer
from .config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS, METRICS_PORT

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("ai-event-consumer")

TOPICS = ("anomalies.events", "ai.findings", "rca.events")
PROCESSED = Counter("ai_events_processed_total", "AI events stored", ["event_type", "result"])
CONSUMER_UP = Gauge("ai_event_consumer_up", "Whether the AI event consumer is running")


def store(connection: psycopg.Connection, event: dict) -> None:
    payload = event.get("payload") or {}
    event_type = event.get("event_type", "")
    common = (event["message_id"], event["observed_at"], event.get("site_id"), event.get("asset_id"))
    if event_type == "anomaly.detected":
        connection.execute(
            """INSERT INTO ai.anomalies
               (event_id,observed_at,site_id,asset_id,metric_name,actual_value,baseline_value,
                anomaly_score,severity,model_name,payload)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb) ON CONFLICT DO NOTHING""",
            (*common, payload["metric_name"], payload.get("actual_value"), payload.get("baseline_value"),
             payload.get("anomaly_score"), payload.get("severity", "warning"),
             payload.get("model_name", "IsolationForest-demo"), json.dumps(payload)),
        )
    elif event_type == "forecast.prediction":
        connection.execute(
            """INSERT INTO ai.forecasts
               (event_id,generated_at,site_id,asset_id,metric_name,horizon_hours,predicted_value,
                threshold_value,predicted_breach_at,confidence,model_name,payload)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb) ON CONFLICT DO NOTHING""",
            (*common, payload["metric_name"], payload.get("horizon_hours", 24), payload.get("predicted_value"),
             payload.get("threshold_value"), payload.get("predicted_breach_at"), payload.get("confidence"),
             payload.get("model_name", "linear-trend-demo"), json.dumps(payload)),
        )
    elif event_type == "incident.correlated":
        connection.execute(
            """INSERT INTO events.correlated_incidents
               (event_id,incident_key,started_at,site_id,severity,status,root_asset_id,
                correlated_event_count,impacted_services,summary,correlation_confidence,payload)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
               ON CONFLICT (incident_key) DO UPDATE SET status=excluded.status,
                 correlated_event_count=excluded.correlated_event_count,payload=excluded.payload""",
            (event["message_id"], payload["incident_key"], event["observed_at"], event.get("site_id"),
             payload.get("severity", "critical"), payload.get("status", "open"), payload.get("root_asset_id"),
             payload.get("correlated_event_count", 1), payload.get("impacted_services", []),
             payload.get("summary", "Correlated incident"), payload.get("correlation_confidence"), json.dumps(payload)),
        )
    elif event_type == "rca.completed":
        connection.execute(
            """INSERT INTO ai.rca_findings
               (event_id,incident_key,generated_at,site_id,root_asset_id,probable_cause,
                confidence,service_impact,evidence,recommendation,payload)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb) ON CONFLICT DO NOTHING""",
            (event["message_id"], payload["incident_key"], event["observed_at"], event.get("site_id"),
             payload.get("root_asset_id"), payload["probable_cause"], payload.get("confidence"),
             payload.get("service_impact"), payload.get("evidence", []), payload.get("recommendation"), json.dumps(payload)),
        )
    else:
        raise ValueError(f"unsupported AI event_type: {event_type}")


def main() -> None:
    start_http_server(METRICS_PORT)
    consumer = KafkaConsumer(
        *TOPICS, bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id=os.getenv("AI_EVENT_CONSUMER_GROUP", "ardmatrix-ai-event-store-v1"),
        auto_offset_reset="earliest", enable_auto_commit=False,
        value_deserializer=json_deserializer,
    )
    CONSUMER_UP.set(1)
    LOG.info("consuming %s", ", ".join(TOPICS))
    for message in consumer:
        event_type = str((message.value or {}).get("event_type", "unknown"))
        try:
            with psycopg.connect(DATABASE_URL) as connection:
                store(connection, message.value)
            consumer.commit()
            PROCESSED.labels(event_type, "stored").inc()
        except Exception:
            PROCESSED.labels(event_type, "failed").inc()
            LOG.exception("failed to store %s offset %s", message.topic, message.offset)


if __name__ == "__main__":
    main()
