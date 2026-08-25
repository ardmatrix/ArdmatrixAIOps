# ARDMATRIX Data Center AIOps

Read `PROJECT_CONTEXT.md` completely before changing this repository.

## Project rules

- Grafana is the primary UI; do not create custom HTML dashboards.
- Keep the V1 stack reliable within an 8 GB Docker Desktop allocation on the
  local Intel Mac workstation.
- Prometheus is for live scraped monitoring, Kafka is the streaming backbone,
  and TimescaleDB is the durable operational and analytical store.
- Airflow schedules data preparation and ML workflows; it is not the real-time
  metric processor.
- Keep ingestion source-agnostic and normalize records into shared schemas.
- Model topology explicitly and connect faults to application and business
  service impact.
- Clearly identify simulated telemetry in schemas and dashboards.
- Never commit real passwords or generated runtime data.

## Verification

- Run `docker compose config --quiet` after Compose changes.
- Add health checks to long-running services where practical.
- Keep tests deterministic and CPU-only unless requirements change.
