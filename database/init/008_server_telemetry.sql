CREATE TABLE IF NOT EXISTS telemetry.server_metrics (
    observed_at timestamptz NOT NULL,
    server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
    server_key text NOT NULL,
    cpu_utilization_percent double precision NOT NULL CHECK (cpu_utilization_percent BETWEEN 0 AND 100),
    memory_used_bytes bigint NOT NULL CHECK (memory_used_bytes >= 0),
    memory_utilization_percent double precision NOT NULL CHECK (memory_utilization_percent BETWEEN 0 AND 100),
    disk_used_bytes bigint NOT NULL CHECK (disk_used_bytes >= 0),
    disk_utilization_percent double precision NOT NULL CHECK (disk_utilization_percent BETWEEN 0 AND 100),
    storage_free_bytes bigint NOT NULL CHECK (storage_free_bytes >= 0),
    disk_read_iops double precision NOT NULL CHECK (disk_read_iops >= 0),
    disk_write_iops double precision NOT NULL CHECK (disk_write_iops >= 0),
    disk_latency_ms double precision NOT NULL CHECK (disk_latency_ms >= 0),
    load_1m double precision NOT NULL CHECK (load_1m >= 0),
    network_receive_bps bigint NOT NULL CHECK (network_receive_bps >= 0),
    network_transmit_bps bigint NOT NULL CHECK (network_transmit_bps >= 0),
    bandwidth_utilization_percent double precision NOT NULL CHECK (bandwidth_utilization_percent BETWEEN 0 AND 100),
    network_latency_ms double precision NOT NULL CHECK (network_latency_ms >= 0),
    packet_loss_percent double precision NOT NULL CHECK (packet_loss_percent BETWEEN 0 AND 100),
    temperature_celsius double precision NOT NULL,
    humidity_percent double precision NOT NULL CHECK (humidity_percent BETWEEN 0 AND 100),
    airflow_cfm double precision NOT NULL CHECK (airflow_cfm >= 0),
    pue double precision NOT NULL CHECK (pue >= 1),
    power_consumption_watts double precision NOT NULL CHECK (power_consumption_watts >= 0),
    uptime_seconds bigint NOT NULL CHECK (uptime_seconds >= 0),
    uptime_percent double precision NOT NULL CHECK (uptime_percent BETWEEN 0 AND 100),
    error_rate_per_minute double precision NOT NULL CHECK (error_rate_per_minute >= 0),
    available boolean NOT NULL,
    source text NOT NULL,
    is_simulated boolean NOT NULL,
    event_id uuid NOT NULL,
    PRIMARY KEY (observed_at, server_id),
    UNIQUE (observed_at, event_id)
);

SELECT create_hypertable(
    'telemetry.server_metrics',
    by_range('observed_at'),
    if_not_exists => true
);

CREATE INDEX IF NOT EXISTS server_metrics_server_time_idx
    ON telemetry.server_metrics (server_id, observed_at DESC);

SELECT add_retention_policy(
    'telemetry.server_metrics',
    INTERVAL '30 days',
    if_not_exists => true
);
