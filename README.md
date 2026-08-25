# ARDMATRIX Data Center AIOps

A customer-ready demo that connects infrastructure and application telemetry to
anomaly detection, prediction, event correlation, root-cause analysis, service
impact, and operational recommendations.

## Prerequisites

- macOS on an Intel Mac
- Apple Command Line Tools
- Docker Desktop for Mac
- Docker Compose v2 or newer

## Start the base platform

1. Copy `.env.example` to `.env` and set local passwords. A development `.env`
   is already present in a fresh local scaffold and is ignored by Git.
2. Validate the configuration:

   ```bash
   docker compose config --quiet
   ```

3. Start the services:

   ```bash
   docker compose up -d
   docker compose ps
   ```

4. Open:

   - Grafana: <http://localhost:3000>
   - Prometheus: <http://localhost:9090>
   - TimescaleDB: `localhost:5432`
   - Kafka: `localhost:9092`

The local development Grafana credentials are `admin` / `admin`; change them
before sharing or deploying the environment.

## Stop the platform

```bash
docker compose down
```

Named volumes preserve service data. Use `docker compose down --volumes` only
when intentionally resetting all local platform state.

## Project status

The repository currently provides the base platform foundation. Ingestion,
telemetry generation, ML, Kubernetes workloads, correlation, RCA, service
impact, and customer dashboards will be implemented in subsequent stages.
