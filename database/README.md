# Inventory database

The `inventory` schema uses ordinary PostgreSQL relational tables. It is not a
TimescaleDB hypertable model. TimescaleDB is available in the same PostgreSQL
instance for future time-series telemetry.

Initialization order:

1. `001_extensions.sql` creates extensions and schemas.
2. `002_inventory.sql` creates the normalized inventory model.
3. `003_demo_inventory.sql` adds deterministic, explicitly simulated demo data.
4. `004_ardmatrixlab_server.sql` adds the Delhi hands-on lab server and its
   hardware components.

The inventory model covers facilities, servers and hardware components,
network and storage devices, hypervisors and VMs, Kubernetes resources,
applications, business services, discovery provenance, ownership, and change
history. Cross-domain dependency relationships are intentionally deferred to
the topology phase.

Useful validation queries:

```sql
SELECT * FROM inventory.inventory_summary ORDER BY entity_type;
SELECT * FROM inventory.server_capacity ORDER BY server_key;
```

The seed script is idempotent and can be run repeatedly during development.
