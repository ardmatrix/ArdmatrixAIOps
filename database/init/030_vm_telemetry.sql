BEGIN;

CREATE TABLE IF NOT EXISTS telemetry.vm_metrics (
    observed_at timestamptz NOT NULL,
    vm_id uuid NOT NULL REFERENCES inventory.virtual_machines(id) ON DELETE CASCADE,
    vm_key text NOT NULL,
    cpu_utilization_percent double precision,
    memory_utilization_percent double precision,
    storage_utilization_percent double precision,
    uptime_percent double precision,
    available boolean NOT NULL DEFAULT true,
    source text NOT NULL,
    is_simulated boolean NOT NULL DEFAULT false,
    event_id uuid NOT NULL,
    PRIMARY KEY (observed_at,event_id)
);

CREATE INDEX IF NOT EXISTS vm_metrics_vm_time_idx
    ON telemetry.vm_metrics(vm_id,observed_at DESC);

COMMIT;
