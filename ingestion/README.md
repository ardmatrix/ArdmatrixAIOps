# Inventory CSV ingestion

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
