BEGIN;

ALTER TABLE inventory.sites
  ADD COLUMN IF NOT EXISTS region text,
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS health_status text NOT NULL DEFAULT 'healthy',
  ADD COLUMN IF NOT EXISTS facility_power_capacity_kw numeric(12,2),
  ADD COLUMN IF NOT EXISTS facility_power_used_kw numeric(12,2),
  ADD COLUMN IF NOT EXISTS cooling_capacity_kw numeric(12,2),
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS humidity_pct numeric(5,2),
  ADD COLUMN IF NOT EXISTS pue numeric(4,2),
  ADD COLUMN IF NOT EXISTS monitoring_coverage_pct numeric(5,2) DEFAULT 100,
  ADD COLUMN IF NOT EXISTS inventory_completeness_pct numeric(5,2) DEFAULT 100;

ALTER TABLE inventory.racks
  ADD COLUMN IF NOT EXISTS health_status text NOT NULL DEFAULT 'healthy',
  ADD COLUMN IF NOT EXISTS used_rack_units smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS current_power_watts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS humidity_pct numeric(5,2),
  ADD COLUMN IF NOT EXISTS monitoring_status text NOT NULL DEFAULT 'monitored';

ALTER TABLE inventory.servers
  ADD COLUMN IF NOT EXISTS health_status text NOT NULL DEFAULT 'healthy',
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS criticality text NOT NULL DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS monitoring_status text NOT NULL DEFAULT 'monitored',
  ADD COLUMN IF NOT EXISTS warranty_expiry date,
  ADD COLUMN IF NOT EXISTS end_of_support date,
  ADD COLUMN IF NOT EXISTS business_service text;

ALTER TABLE inventory.virtual_machines
  ADD COLUMN IF NOT EXISTS health_status text NOT NULL DEFAULT 'healthy',
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS criticality text NOT NULL DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS monitoring_status text NOT NULL DEFAULT 'monitored',
  ADD COLUMN IF NOT EXISTS cpu_utilization_pct numeric(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS memory_utilization_pct numeric(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS storage_utilization_pct numeric(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS uptime_pct numeric(6,3) NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS snapshot_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS backup_status text NOT NULL DEFAULT 'protected';

CREATE TABLE IF NOT EXISTS events.inventory_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_key text NOT NULL UNIQUE,
  entity_type text NOT NULL CHECK (entity_type IN ('site','rack','server','vm')),
  entity_id uuid NOT NULL,
  severity text NOT NULL CHECK (severity IN ('info','warning','critical')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved')),
  title text NOT NULL,
  description text,
  metric_name text,
  metric_value double precision,
  threshold_value double precision,
  opened_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  is_simulated boolean NOT NULL DEFAULT false,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS inventory_alerts_entity_idx
  ON events.inventory_alerts(entity_type, entity_id, status);
CREATE INDEX IF NOT EXISTS inventory_alerts_open_idx
  ON events.inventory_alerts(opened_at DESC) WHERE status <> 'resolved';

UPDATE inventory.sites SET
  region = coalesce(region, attributes->>'region', address->>'city'),
  environment = coalesce(attributes->>'environment', environment),
  health_status = coalesce(attributes->>'operational_health', health_status),
  facility_power_capacity_kw = coalesce(facility_power_capacity_kw, (attributes->>'power_capacity_kw')::numeric),
  facility_power_used_kw = coalesce(facility_power_used_kw, (attributes->>'power_used_kw')::numeric),
  cooling_capacity_kw = coalesce(cooling_capacity_kw, (attributes->>'cooling_capacity_kw')::numeric),
  temperature_c = coalesce(temperature_c, (attributes->>'temperature_c')::numeric),
  humidity_pct = coalesce(humidity_pct, (attributes->>'humidity_pct')::numeric),
  pue = coalesce(pue, (attributes->>'pue')::numeric),
  monitoring_coverage_pct = coalesce((attributes->>'monitoring_coverage_pct')::numeric, monitoring_coverage_pct),
  inventory_completeness_pct = coalesce((attributes->>'inventory_completeness_pct')::numeric, inventory_completeness_pct);

UPDATE inventory.racks SET
  used_rack_units = coalesce((attributes->>'used_rack_units')::smallint, used_rack_units),
  current_power_watts = coalesce((attributes->>'current_power_watts')::integer, current_power_watts);

UPDATE inventory.servers SET
  health_status = CASE status WHEN 'failed' THEN 'critical' WHEN 'maintenance' THEN 'warning' ELSE health_status END,
  environment = coalesce(attributes->>'environment', environment),
  criticality = coalesce(attributes->>'criticality', criticality),
  monitoring_status = coalesce(attributes->>'monitoring_status', monitoring_status),
  warranty_expiry = coalesce(warranty_expiry, (attributes->>'warranty_expiry')::date),
  end_of_support = coalesce(end_of_support, (attributes->>'end_of_support')::date),
  business_service = coalesce(attributes->>'business_service', business_service);

CREATE OR REPLACE VIEW inventory.technical_hierarchy AS
SELECT s.id site_id,s.site_key,s.name site_name,s.region,s.environment site_environment,s.health_status site_health,
       rm.id room_id,rm.name room_name,dr.id row_id,dr.name row_name,r.id rack_id,r.rack_key,r.name rack_name,
       r.health_status rack_health,sv.id server_id,sv.server_key,sv.hostname,sv.health_status server_health,
       h.id hypervisor_id,h.hypervisor_key,vm.id vm_id,vm.vm_key,vm.name vm_name,vm.health_status vm_health
FROM inventory.sites s
LEFT JOIN inventory.rooms rm ON rm.site_id=s.id
LEFT JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
LEFT JOIN inventory.racks r ON r.row_id=dr.id
LEFT JOIN inventory.servers sv ON sv.rack_id=r.id
LEFT JOIN inventory.hypervisors h ON h.server_id=sv.id
LEFT JOIN inventory.virtual_machines vm ON vm.hypervisor_id=h.id;

CREATE OR REPLACE VIEW inventory.data_center_operational_overview AS
SELECT s.id,s.site_key,s.name,s.region,s.environment,s.health_status,s.latitude,s.longitude,
       o.name owner,s.facility_power_capacity_kw,s.facility_power_used_kw,s.cooling_capacity_kw,
       s.temperature_c,s.humidity_pct,s.pue,s.monitoring_coverage_pct,s.inventory_completeness_pct,
       count(DISTINCT r.id) rack_count,count(DISTINCT sv.id) server_count,count(DISTINCT vm.id) vm_count,
       count(DISTINCT a.id) FILTER (WHERE a.status<>'resolved') open_alerts,
       count(DISTINCT a.id) FILTER (WHERE a.status<>'resolved' AND a.severity='critical') critical_alerts,
       count(DISTINCT sv.id) FILTER (WHERE sv.monitoring_status='unmonitored') +
         count(DISTINCT vm.id) FILTER (WHERE vm.monitoring_status='unmonitored') unmonitored_assets,
       s.last_seen_at,s.is_simulated
FROM inventory.sites s
LEFT JOIN inventory.owners o ON o.id=s.owner_id
LEFT JOIN inventory.rooms rm ON rm.site_id=s.id
LEFT JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
LEFT JOIN inventory.racks r ON r.row_id=dr.id
LEFT JOIN inventory.servers sv ON sv.rack_id=r.id
LEFT JOIN inventory.hypervisors h ON h.server_id=sv.id
LEFT JOIN inventory.virtual_machines vm ON vm.hypervisor_id=h.id
LEFT JOIN events.inventory_alerts a ON (a.entity_type='site' AND a.entity_id=s.id)
  OR (a.entity_type='rack' AND a.entity_id=r.id) OR (a.entity_type='server' AND a.entity_id=sv.id)
  OR (a.entity_type='vm' AND a.entity_id=vm.id)
GROUP BY s.id,o.name;

CREATE OR REPLACE VIEW inventory.rack_operational_overview AS
SELECT r.id,r.rack_key,r.name,s.site_key,s.name site_name,rm.name room_name,dr.name row_name,
       r.health_status,r.status,r.rack_units,r.used_rack_units,r.max_power_watts,r.current_power_watts,
       r.temperature_c,r.humidity_pct,r.monitoring_status,count(DISTINCT sv.id) server_count,
       count(DISTINCT vm.id) vm_count,count(DISTINCT a.id) FILTER (WHERE a.status<>'resolved') open_alerts,
       r.updated_at,r.is_simulated
FROM inventory.racks r JOIN inventory.data_center_rows dr ON dr.id=r.row_id
JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
LEFT JOIN inventory.servers sv ON sv.rack_id=r.id LEFT JOIN inventory.hypervisors h ON h.server_id=sv.id
LEFT JOIN inventory.virtual_machines vm ON vm.hypervisor_id=h.id
LEFT JOIN events.inventory_alerts a ON (a.entity_type='rack' AND a.entity_id=r.id)
  OR (a.entity_type='server' AND a.entity_id=sv.id) OR (a.entity_type='vm' AND a.entity_id=vm.id)
GROUP BY r.id,s.site_key,s.name,rm.name,dr.name;

CREATE OR REPLACE VIEW inventory.server_operational_overview AS
SELECT sv.id,sv.server_key,sv.hostname,s.site_key,s.name site_name,r.rack_key,r.name rack_name,
       sv.health_status,sv.status,sv.environment,sv.criticality,sv.monitoring_status,sv.manufacturer,sv.model,
       sv.serial_number,sv.asset_tag,sv.operating_system,sv.operating_system_version,sv.rack_unit_start,
       sc.physical_cores,sc.logical_processors,sc.ram_bytes,sc.local_storage_bytes,sc.gpu_count,
       lm.cpu_utilization_percent,lm.memory_utilization_percent,lm.disk_utilization_percent,
       lm.temperature_celsius,lm.power_consumption_watts,lm.uptime_percent,lm.available,
       count(DISTINCT vm.id) vm_count,count(DISTINCT a.id) FILTER (WHERE a.status<>'resolved') open_alerts,
       o.name owner,sv.business_service,sv.warranty_expiry,sv.end_of_support,sv.last_seen_at,sv.is_simulated
FROM inventory.servers sv JOIN inventory.racks r ON r.id=sv.rack_id
JOIN inventory.data_center_rows dr ON dr.id=r.row_id JOIN inventory.rooms rm ON rm.id=dr.room_id
JOIN inventory.sites s ON s.id=rm.site_id LEFT JOIN inventory.owners o ON o.id=sv.owner_id
LEFT JOIN inventory.server_capacity sc ON sc.id=sv.id LEFT JOIN inventory.hypervisors h ON h.server_id=sv.id
LEFT JOIN inventory.virtual_machines vm ON vm.hypervisor_id=h.id
LEFT JOIN LATERAL (SELECT m.* FROM telemetry.server_metrics m WHERE m.server_id=sv.id ORDER BY observed_at DESC LIMIT 1) lm ON true
LEFT JOIN events.inventory_alerts a ON (a.entity_type='server' AND a.entity_id=sv.id) OR (a.entity_type='vm' AND a.entity_id=vm.id)
GROUP BY sv.id,s.site_key,s.name,r.rack_key,r.name,sc.physical_cores,sc.logical_processors,sc.ram_bytes,
  sc.local_storage_bytes,sc.gpu_count,lm.cpu_utilization_percent,lm.memory_utilization_percent,
  lm.disk_utilization_percent,lm.temperature_celsius,lm.power_consumption_watts,lm.uptime_percent,lm.available,o.name;

CREATE OR REPLACE VIEW inventory.vm_operational_overview AS
SELECT vm.id,vm.vm_key,vm.name,vm.hostname,s.site_key,s.name site_name,r.rack_key,r.name rack_name,
       sv.server_key,sv.hostname physical_host,h.hypervisor_type,h.cluster_name,vm.health_status,vm.status,
       vm.environment,vm.criticality,vm.monitoring_status,vm.vcpu_count,vm.memory_bytes,
       vm.provisioned_storage_bytes,vm.cpu_utilization_pct,vm.memory_utilization_pct,
       vm.storage_utilization_pct,vm.uptime_pct,vm.snapshot_count,vm.backup_status,vm.operating_system,
       vm.operating_system_version,vm.ip_addresses,count(DISTINCT a.id) FILTER (WHERE a.status<>'resolved') open_alerts,
       o.name owner,vm.last_seen_at,vm.is_simulated
FROM inventory.virtual_machines vm JOIN inventory.hypervisors h ON h.id=vm.hypervisor_id
JOIN inventory.servers sv ON sv.id=h.server_id JOIN inventory.racks r ON r.id=sv.rack_id
JOIN inventory.data_center_rows dr ON dr.id=r.row_id JOIN inventory.rooms rm ON rm.id=dr.room_id
JOIN inventory.sites s ON s.id=rm.site_id LEFT JOIN inventory.owners o ON o.id=vm.owner_id
LEFT JOIN events.inventory_alerts a ON a.entity_type='vm' AND a.entity_id=vm.id
GROUP BY vm.id,s.site_key,s.name,r.rack_key,r.name,sv.server_key,sv.hostname,h.hypervisor_type,h.cluster_name,o.name;

COMMIT;
