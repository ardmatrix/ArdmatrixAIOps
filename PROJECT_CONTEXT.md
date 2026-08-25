# ARDMATRIX Data Center AIOps — Project Context

## Objective
Build a customer-ready Data Center AIOps demo showing:

**Inventory → Observe → Detect → Predict → Correlate → RCA → Recommend**

Grafana is the primary UI. Do not build custom HTML dashboards for the AIOps demo.

## Demo Environment
- Intel Mac workstation
- 32 GB host RAM, with an initial 8 GB Docker Desktop allocation
- macOS
- Docker Desktop / Docker Compose
- Lightweight local Kubernetes
- CPU-only AI/ML initially

## Core Stack
- PostgreSQL + TimescaleDB
- Apache Kafka
- Prometheus
- Grafana
- Apache Airflow
- Python / Pandas / scikit-learn
- Isolation Forest initially
- Docker
- Kubernetes
- Node Exporter
- Windows Exporter
- SNMP Exporter
- kube-state-metrics
- cAdvisor/container metrics
- Kubernetes API
- SSH/API/custom Python collectors

## Architecture

```text
DATA CENTER SOURCES
├── Servers / VMs → Node Exporter / Windows Exporter / SSH
├── Network → SNMP / API / SSH
├── Kubernetes → K8s API / kube-state-metrics / cAdvisor
├── Applications → API / metrics / logs
└── Files → CSV / JSON / Parquet
              ↓
       DATA LANDING ZONE
              ↓
       INGESTION ENGINE
 Validate → Normalize → Deduplicate → Enrich
              ↓
            KAFKA
              │
      ┌───────┼────────────┐
      ▼       ▼            ▼
TimescaleDB  ML       Events/Alerts
              │            │
         Anomalies     Correlation
         Forecast           │
              └──────────── RCA
                    │
                    ▼
                  Grafana

TimescaleDB → Airflow → training / forecasting / retraining / data quality
```

## Landing Zone
Initial folders:

```text
landing/
├── server/
├── network/
├── kubernetes/
├── applications/
├── inventory/
├── topology/
└── errors/
```

Python ingestion should validate schema/timestamps/identifiers, normalize fields and units, deduplicate, enrich with site/application/service/topology, route bad data to errors, and publish valid records to Kafka.

## Kafka Topics
- server.metrics
- network.metrics
- kubernetes.metrics
- application.metrics
- inventory.events
- topology.events
- alerts.events
- anomalies.events
- ai.findings
- rca.events

## PostgreSQL / TimescaleDB
Store:
- Sites/data centers and racks
- Servers, VMs and network devices
- Interfaces, VLANs, VRFs and subnets
- Kubernetes inventory
- Applications and business services
- Topology/dependencies
- Historical/derived metrics as appropriate
- Alerts, anomalies and forecasts
- Incidents and correlations
- RCA results
- Service impact
- AI findings

Prometheus handles scraping/live monitoring; Kafka handles streaming; TimescaleDB provides durable operational/analytical history.

## Inventory Model

Physical:
- Data centers/sites
- Racks
- Physical servers
- Switches/routers
- Firewalls/load balancers
- Storage

Virtual:
- Hypervisors
- Virtual machines

Kubernetes:
- Clusters
- Nodes
- Namespaces
- Deployments
- StatefulSets
- DaemonSets
- Services
- Pods
- Containers

Applications:
- Applications
- Microservices
- Databases
- Business services

Key dependency example:

```text
CRM Business Service
→ CRM Application
→ CRM API
→ Kubernetes Service
→ Deployment
→ Pod
→ Container
→ Kubernetes Node
→ VM / Physical Server
→ Rack
→ Access Switch
→ Core Network
→ Data Center
```

## Demo Scale
Use a transparent mix of real and simulated telemetry:
- 3 data centers
- ~1,200 simulated servers
- ~250 VMs
- ~40 network devices
- 3 logical Kubernetes clusters
- ~12 K8s nodes
- ~30 namespaces
- ~80 deployments
- ~150 pods
- 200+ containers
- ~20 applications
- ~10 business services

## Monitoring

Servers/VMs:
CPU, memory, disk, filesystem, disk I/O, network RX/TX, load, processes, uptime, availability.

Network:
Availability, interface state/utilization, errors, CRC errors, drops, latency, CPU, memory, temperature, flaps.

Kubernetes:
Cluster/node health, pod/container CPU and memory, restarts, Pending/Failed, OOMKilled, CrashLoopBackOff, deployment replicas/availability.

Applications:
Use CRM demo with CRM-WEB, CRM-API and CRM-DB. Monitor availability, response time, request rate, error rate, HTTP 4xx/5xx, DB response time and connections.

## AI/ML Capabilities
1. Anomaly Detection
2. Forecasting
3. Dynamic Baselines
4. Capacity Prediction
5. Event Correlation
6. Root Cause Analysis
7. Service Impact Analysis
8. Noise Reduction
9. Change Correlation
10. AI-assisted operations later

Use Isolation Forest initially.

## Airflow
Airflow orchestrates ML; it is not the real-time stream processor.

DAG responsibilities:
- Historical data preparation
- Data quality
- Feature engineering
- Model training/validation
- Scheduled retraining
- Forecasting
- Capacity predictions
- Model health/drift

Real-time inference:

```text
Kafka → Python ML Consumer → latest model → anomaly score → anomalies.events
```

## Customer Demo Incidents

1. Memory Leak
AI detects abnormal growth before a static threshold and forecasts threshold breach.

2. Network Degradation
CRC errors/drops/latency affect a K8s node, pods and CRM; correlate events and identify switch/interface RCA.

3. Kubernetes Failure
Container memory increase → OOMKilled → pod restart → application latency → service degradation.

4. Disk Capacity
Forecast DB disk exhaustion days in advance.

5. Multi-Alarm RCA
One underlying network issue creates many symptoms; reduce them to one correlated incident with service impact, probable root cause, confidence and recommendation.

6. Change Correlation
CRM deployment followed by errors/restarts/degradation; identify temporal/dependency correlation.

## Grafana Dashboards
1. Data Center Overview
2. Infrastructure Inventory
3. Server & VM Health
4. Network Operations
5. Kubernetes & Containers
6. Application & Service Health
7. AI Anomalies
8. Predictive Capacity
9. Incident Correlation
10. RCA & Service Impact
11. Ingestion Health

Ingestion Health should show records received/processed/rejected, schema errors, duplicates, late events, Kafka lag, source availability and last ingestion time.

## Kubernetes Strategy
For demo stability:

```text
Intel Mac
└── Docker Desktop
    ├── Docker Compose — AIOps Platform
    │   ├── Kafka
    │   ├── TimescaleDB
    │   ├── Prometheus
    │   ├── Grafana
    │   ├── Airflow
    │   └── Python AIOps services
    └── Lightweight Kubernetes — observed workload
        ├── CRM namespace
        ├── CRM web pods
        ├── CRM API pods
        ├── supporting DB/service
        └── kube-state-metrics
```

Do not initially put the entire AIOps platform in Kubernetes.

## AI Assistant — Later
After telemetry/topology/correlation/RCA are reliable, add an LLM/RAG operational assistant for questions such as “Why is CRM slow?”. Keep infrastructure-changing actions human-approved initially.

## Demo Story
1. Show data-center inventory.
2. Show unified health.
3. Explain ingestion/landing zone.
4. Introduce memory anomaly below static threshold.
5. Show anomaly detection.
6. Show forecast.
7. Introduce network degradation.
8. Generate downstream symptoms.
9. Show correlation/noise reduction.
10. Show service impact.
11. Show probable RCA.
12. Show recommendation.
13. Later ask AI assistant to explain the incident.

## Development Principles
- Grafana is the UI.
- PostgreSQL/TimescaleDB is a core data store.
- Kafka is the streaming/event backbone.
- Airflow orchestrates ML, not per-metric real-time processing.
- Keep ingestion source-agnostic.
- Normalize telemetry into common schemas.
- Model topology/dependencies explicitly.
- Connect technical failures to application/business-service impact.
- Clearly label simulated vs live telemetry.
- Optimize V1 for reliability within an 8 GB Docker Desktop allocation on the
  local Intel Mac.
- Avoid Spark/Flink/Hadoop/OpenSearch initially unless a requirement justifies them.

## Initial Build Order
1. macOS + Apple Command Line Tools
2. Docker Desktop
3. Repository structure
4. PostgreSQL/TimescaleDB
5. Kafka
6. Prometheus
7. Grafana
8. Landing zone
9. Python ingestion/normalization
10. Metric generators
11. Server/VM monitoring
12. Network monitoring
13. Airflow
14. Isolation Forest
15. Forecasting
16. Kubernetes demo environment
17. Kubernetes monitoring
18. Application/service model
19. Event correlation
20. RCA
21. Service impact
22. Customer-ready Grafana dashboards
23. AI assistant/RAG later

## Repository Structure

```text
dc-aiops/
├── AGENTS.md
├── PROJECT_CONTEXT.md
├── ARCHITECTURE.md
├── README.md
├── .env
├── docker-compose.yml
├── landing/
├── database/
├── kafka/
├── prometheus/
├── grafana/
├── airflow/
│   └── dags/
├── collectors/
├── consumers/
├── ml/
├── kubernetes/
├── simulators/
├── services/
│   ├── correlation/
│   ├── rca/
│   └── service-impact/
├── scripts/
└── tests/
```

## Immediate Next Step
Complete Docker Desktop setup on macOS, validate the base Docker Compose stack,
and verify all four foundation services before adding ingestion or AI/ML
functionality.
