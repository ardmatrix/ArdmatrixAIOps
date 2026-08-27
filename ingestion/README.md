# Inventory CSV ingestion

## Unified source pipeline

The inventory CSV watcher remains the authoritative bulk inventory path. A
separate source-agnostic pipeline accepts operational feeds:

```text
CSV / JSON / API / Telemetry / SNMP / Logs
  -> validation -> normalized envelope -> allow-listed Kafka topic
  -> database audit + Prometheus metrics -> consumers / ML / Grafana
```

HTTP ingestion is available on `http://localhost:8091` and requires the token
configured as `SOURCE_API_TOKEN`:

```bash
curl -X POST http://localhost:8091/ingest/snmp \
  -H 'Authorization: Bearer demo-local-token' \
  -H 'Content-Type: application/json' \
  -d '{
    "source_system":"chicago-snmp-poller",
    "site_id":"dc-chicago",
    "asset_id":"dc-chicago-core-01",
    "event_type":"interface.status",
    "payload":{"interface":"Gi1/0/48","oper_status":"down"}
  }'
```

Other endpoints are `/ingest/api`, `/ingest/telemetry`, and `/ingest/logs`.
Clients may select only an allow-listed topic. API credentials stay in the
collector and are never sent in event payloads.

For file feeds, place completed `.csv` or `.json` files under:

```text
landing/server/incoming       -> server.metrics
landing/network/incoming      -> network.metrics
landing/kubernetes/incoming   -> kubernetes.metrics
landing/applications/incoming -> application.metrics
landing/topology/incoming     -> topology.events
```

Files move to `archive` after publication or `errors` with a JSON report after
validation failure. Upload through a temporary `.uploading` filename and rename
it only when complete, so the watcher cannot read a partial transfer.

## Ten-day traffic simulator

`kafka-traffic-simulator` emits a 24-event batch every 15 minutes for exactly
10 days. Each batch covers four sites and includes server telemetry, SNMP
interface metrics, Kubernetes health, application performance and logs. Its
schedule and counters are persisted in `ingestion.simulator_runs`, so restarting
Docker does not restart or extend the ten-day window.

Change `SIMULATOR_RUN_KEY` to deliberately start a new independent run. For a
short test only, override `SIMULATOR_INTERVAL_SECONDS`; the production demo
default is `900` seconds.

Two lightweight services implement the initial customer inventory pipeline:

- `inventory-watcher` polls `landing/inventory/incoming`, waits for files to be
  stable, validates them against the version-controlled CSV templates, records
  an audit run, and publishes normalized row envelopes to `inventory.events`.
- `inventory-consumer` consumes those messages, performs idempotent PostgreSQL
  upserts, records row failures, and commits Kafka offsets after the database
  transaction completes.

The watcher archives successful and duplicate files and moves invalid files to
`landing/inventory/errors` with a JSON validation report. SHA-256 file checksums
prevent an unchanged file from being loaded twice. Message IDs prevent Kafka
redelivery from duplicating database writes.

## Currently supported CSV types

- `owners`
- `sites`, `rooms`, `rows`, `racks`
- `servers`
- `server_cpus`, `server_memory`, `server_gpus`, `server_storage`
- `network_devices`, `network_interfaces`
- `hypervisors`, `virtual_machines`

The remaining templates are the next implementation slice: network segments,
storage systems, Kubernetes, applications, components, and business services.

## Hands-on import

Use a timestamp or customer identifier after the supported entity prefix:

```bash
cp landing/inventory/templates/servers.csv \
  landing/inventory/incoming/servers_customer1_20260824.csv.uploading
mv landing/inventory/incoming/servers_customer1_20260824.csv.uploading \
  landing/inventory/incoming/servers_customer1_20260824.csv
```

Inspect recent runs:

```bash
docker compose exec timescaledb sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT * FROM ingestion.file_run_summary LIMIT 20"'
```

Metrics are available locally at:

- Watcher: <http://localhost:9101/metrics>
- Consumer: <http://localhost:9102/metrics>
