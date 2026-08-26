WITH server_inventory AS (
    SELECT sv.id AS server_id,
           sv.server_key,
           coalesce(sc.ram_bytes, 0)::bigint AS ram_bytes,
           coalesce(sc.local_storage_bytes, 0)::bigint AS storage_bytes,
           greatest(coalesce(sc.logical_processors, 1), 1)::integer AS processors,
           abs(hashtext(sv.server_key))::bigint AS seed
    FROM inventory.servers sv
    JOIN inventory.server_capacity sc ON sc.id = sv.id
    WHERE sv.status = 'active'
), samples AS (
    SELECT generate_series(
        date_trunc('minute', now() - interval '4 days'),
        date_trunc('minute', now() - interval '5 minutes'),
        interval '5 minutes'
    ) AS observed_at
), calculated AS (
    SELECT sample.observed_at,
           server.server_id,
           server.server_key,
           greatest(2.0, least(95.0,
               42.0 + 25.0 * sin(extract(epoch FROM sample.observed_at) / 7200.0
                   + (server.seed % 360) * pi() / 180.0))) AS cpu_percent,
           greatest(10.0, least(96.0,
               58.0 + 18.0 * sin(extract(epoch FROM sample.observed_at) / 14400.0
                   + (server.seed % 360) * pi() / 180.0))) AS memory_percent,
           greatest(5.0, least(94.0,
               52.0 + 12.0 * sin(extract(epoch FROM sample.observed_at) / 86400.0
                   + (server.seed % 360) * pi() / 180.0))) AS disk_percent,
           server.ram_bytes,
           server.storage_bytes,
           server.processors
    FROM server_inventory server
    CROSS JOIN samples sample
)
INSERT INTO telemetry.server_metrics (
    observed_at, server_id, server_key, cpu_utilization_percent,
    memory_used_bytes, memory_utilization_percent, disk_used_bytes,
    disk_utilization_percent, load_1m, network_receive_bps,
    network_transmit_bps, uptime_seconds, available, source,
    is_simulated, event_id
)
SELECT observed_at,
       server_id,
       server_key,
       round(cpu_percent::numeric, 2)::double precision,
       round(ram_bytes * memory_percent / 100.0)::bigint,
       round(memory_percent::numeric, 2)::double precision,
       round(storage_bytes * disk_percent / 100.0)::bigint,
       round(disk_percent::numeric, 2)::double precision,
       round((cpu_percent / 100.0 * processors)::numeric, 2)::double precision,
       round(8000000 + cpu_percent * 900000)::bigint,
       round(5000000 + cpu_percent * 600000)::bigint,
       greatest(0, round(extract(epoch FROM observed_at - (now() - interval '30 days'))))::bigint,
       true,
       'ardmatrix-demo-backfill',
       true,
       gen_random_uuid()
FROM calculated
ON CONFLICT (observed_at, server_id) DO NOTHING;

UPDATE telemetry.server_metrics sm
SET storage_free_bytes = greatest(0, sc.local_storage_bytes - sm.disk_used_bytes),
    disk_read_iops = round((120 + sm.cpu_utilization_percent * 10
        + 180 * (1 + sin(extract(epoch FROM sm.observed_at) / 1800.0)))::numeric, 2),
    disk_write_iops = round((80 + sm.cpu_utilization_percent * 6
        + 110 * (1 + sin(extract(epoch FROM sm.observed_at) / 2100.0)))::numeric, 2),
    disk_latency_ms = round((1.2 + sm.disk_utilization_percent / 24.0)::numeric, 2),
    bandwidth_utilization_percent = round(least(92, greatest(2,
        sm.cpu_utilization_percent * 0.55 + 15
        + 8 * sin(extract(epoch FROM sm.observed_at) / 2400.0)))::numeric, 2),
    network_latency_ms = round(greatest(1,
        8 + 4 * sin(extract(epoch FROM sm.observed_at) / 3000.0))::numeric, 2),
    packet_loss_percent = round(greatest(0,
        (8 + 4 * sin(extract(epoch FROM sm.observed_at) / 3000.0) - 10) * 0.025)::numeric, 3),
    temperature_celsius = round(least(38, greatest(18,
        20 + sm.cpu_utilization_percent * 0.12
        + 1.5 * sin(extract(epoch FROM sm.observed_at) / 4800.0)))::numeric, 2),
    humidity_percent = round((46 + 7 * sin(extract(epoch FROM sm.observed_at) / 6000.0))::numeric, 2),
    airflow_cfm = round((180 + sm.cpu_utilization_percent * 2.4)::numeric, 2),
    pue = round((1.42 + 0.09 * sin(extract(epoch FROM sm.observed_at) / 18000.0))::numeric, 3),
    power_consumption_watts = round((180 + sm.cpu_utilization_percent * 6.2
        + sm.memory_utilization_percent * 1.1)::numeric, 2),
    uptime_percent = round((99.93 + 0.03 * sin(extract(epoch FROM sm.observed_at) / 30000.0))::numeric, 3),
    error_rate_per_minute = round(greatest(0,
        (sm.cpu_utilization_percent - 70) * 0.015)::numeric, 3)
FROM inventory.server_capacity sc
WHERE sc.id = sm.server_id
  AND sm.observed_at >= now() - interval '4 days 10 minutes';
