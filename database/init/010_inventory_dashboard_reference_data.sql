BEGIN;

-- Dashboard-oriented reference attributes for deterministic simulated inventory.
UPDATE inventory.sites
SET status = CASE site_key WHEN 'dc-delhi' THEN 'maintenance' ELSE 'active' END,
    attributes = attributes || CASE site_key
      WHEN 'dc-mumbai' THEN '{"environment":"production","tier":"Tier III","region":"West India","power_capacity_kw":480,"power_used_kw":326,"cooling_capacity_kw":410,"temperature_c":23.4,"humidity_pct":46,"pue":1.48,"monitoring_coverage_pct":98,"inventory_completeness_pct":96,"operational_health":"healthy"}'::jsonb
      WHEN 'dc-bengaluru' THEN '{"environment":"production","tier":"Tier IV","region":"South India","power_capacity_kw":620,"power_used_kw":511,"cooling_capacity_kw":535,"temperature_c":25.8,"humidity_pct":54,"pue":1.62,"monitoring_coverage_pct":91,"inventory_completeness_pct":89,"operational_health":"degraded"}'::jsonb
      WHEN 'dc-delhi' THEN '{"environment":"disaster_recovery","tier":"Tier III","region":"North India","power_capacity_kw":360,"power_used_kw":194,"cooling_capacity_kw":300,"temperature_c":22.7,"humidity_pct":43,"pue":1.44,"monitoring_coverage_pct":83,"inventory_completeness_pct":86,"operational_health":"maintenance"}'::jsonb
      ELSE '{}'::jsonb END,
    last_seen_at = CASE site_key WHEN 'dc-delhi' THEN now() - interval '3 hours' ELSE now() - interval '5 minutes' END,
    updated_at = now()
WHERE site_key IN ('dc-mumbai','dc-bengaluru','dc-delhi');

UPDATE inventory.racks
SET attributes = attributes || CASE name
      WHEN 'MUM-A01' THEN '{"used_rack_units":31,"current_power_watts":8150}'::jsonb
      WHEN 'BLR-A01' THEN '{"used_rack_units":37,"current_power_watts":10400}'::jsonb
      WHEN 'DEL-A01' THEN '{"used_rack_units":19,"current_power_watts":6100}'::jsonb
      ELSE '{}'::jsonb END,
    updated_at = now();

UPDATE inventory.servers
SET status = CASE server_key WHEN 'srv-blr-001' THEN 'failed' WHEN 'srv-del-gpu-001' THEN 'maintenance' ELSE 'active' END,
    attributes = attributes || CASE server_key
      WHEN 'srv-mum-001' THEN '{"environment":"production","criticality":"high","monitoring_status":"monitored","warranty_expiry":"2028-09-30","end_of_support":"2029-12-31","business_service":"Customer Relationship Management"}'::jsonb
      WHEN 'srv-blr-001' THEN '{"environment":"production","criticality":"critical","monitoring_status":"monitored","warranty_expiry":"2026-10-15","end_of_support":"2027-03-31","business_service":"Customer Relationship Management"}'::jsonb
      WHEN 'srv-del-gpu-001' THEN '{"environment":"disaster_recovery","criticality":"high","monitoring_status":"unmonitored","warranty_expiry":"2027-06-30","end_of_support":"2028-12-31","business_service":"AI Analytics"}'::jsonb
      ELSE '{}'::jsonb END,
    last_seen_at = CASE server_key WHEN 'srv-del-gpu-001' THEN now() - interval '3 hours' ELSE now() - interval '4 minutes' END,
    updated_at = now()
WHERE server_key IN ('srv-mum-001','srv-blr-001','srv-del-gpu-001');

UPDATE inventory.network_devices
SET status = CASE device_key WHEN 'sw-blr-access-01' THEN 'failed' ELSE 'active' END,
    attributes = attributes || CASE device_key
      WHEN 'sw-mum-access-01' THEN '{"monitoring_status":"monitored","firmware_compliance":"compliant","warranty_expiry":"2028-04-30"}'::jsonb
      WHEN 'sw-blr-access-01' THEN '{"monitoring_status":"monitored","firmware_compliance":"upgrade_required","warranty_expiry":"2026-11-30"}'::jsonb
      WHEN 'fw-del-01' THEN '{"monitoring_status":"unmonitored","firmware_compliance":"compliant","warranty_expiry":"2027-08-31"}'::jsonb
      ELSE '{}'::jsonb END,
    last_seen_at = CASE device_key WHEN 'fw-del-01' THEN now() - interval '4 hours' ELSE now() - interval '6 minutes' END,
    updated_at = now()
WHERE device_key IN ('sw-mum-access-01','sw-blr-access-01','fw-del-01');

COMMIT;
