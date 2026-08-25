# Architecture

The authoritative product scope and design constraints are in
[`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md).

## Runtime flow

```text
Sources -> collectors/landing -> validation and normalization -> Kafka
                                                          |-> TimescaleDB
Kafka -> real-time ML -> anomalies -> correlation -> RCA -> service impact
Prometheus ---------------------------------------------------------> Grafana
TimescaleDB -> Airflow -> training/forecasting -> versioned models
```

## Initial deployment

The AIOps platform runs in Docker Compose on Docker Desktop. A lightweight
Kubernetes environment will later provide the observed CRM workload. Keeping
the platform outside Kubernetes reduces demo resource use and operational risk.

The initial Compose foundation contains:

- TimescaleDB for durable inventory and analytical history.
- Kafka in single-node KRaft mode for metric and event streams.
- Prometheus for live metrics and scrape-based monitoring.
- Grafana provisioned with Prometheus and TimescaleDB data sources.

Airflow, collectors, simulators, inference, correlation, RCA, and service-impact
services are added incrementally after this base is verified.
