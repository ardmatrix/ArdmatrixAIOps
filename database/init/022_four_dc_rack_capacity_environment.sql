BEGIN;

-- Rack-level capacity, power and environmental data for the simulated reference estate.
WITH rack_context AS (
  SELECT r.id,r.rack_key,s.site_key,s.temperature_c site_temperature,s.humidity_pct site_humidity,
         row_number() OVER (PARTITION BY s.id ORDER BY r.rack_key) rack_no
  FROM inventory.racks r
  JOIN inventory.data_center_rows dr ON dr.id=r.row_id
  JOIN inventory.rooms rm ON rm.id=dr.room_id
  JOIN inventory.sites s ON s.id=rm.site_id
)
UPDATE inventory.racks r
SET used_rack_units=CASE rc.rack_no WHEN 1 THEN 24 WHEN 2 THEN 26 ELSE 23 END,
    current_power_watts=CASE rc.rack_no WHEN 1 THEN 6840 WHEN 2 THEN 7310 ELSE 6570 END,
    temperature_c=round((rc.site_temperature + CASE rc.rack_no WHEN 1 THEN 0.4 WHEN 2 THEN 1.1 ELSE 0.7 END)::numeric,2),
    humidity_pct=round((rc.site_humidity + CASE rc.rack_no WHEN 1 THEN -1 WHEN 2 THEN 1 ELSE 0 END)::numeric,2),
    health_status=CASE WHEN rc.site_key='dc-singapore' AND rc.rack_no=2 THEN 'warning' ELSE 'healthy' END,
    monitoring_status='monitored',
    attributes=r.attributes || jsonb_build_object(
      'capacity_source','simulated-dcim','power_feed','A+B','power_redundancy','2N',
      'temperature_sensors',3,'humidity_sensors',2,'updated_by','reference-inventory'),
    updated_at=now()
FROM rack_context rc
WHERE r.id=rc.id;

COMMIT;
