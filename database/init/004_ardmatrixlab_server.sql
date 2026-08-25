BEGIN;

INSERT INTO inventory.servers
  (id, server_key, hostname, rack_id, rack_unit_start, rack_unit_height,
   server_type, manufacturer, model, serial_number, asset_tag, architecture,
   operating_system, operating_system_version, status, owner_id, source_id,
   source_native_id, is_simulated, attributes)
VALUES
  ('30000000-0000-0000-0000-000000000004',
   'srv-del-ardmatrixlab',
   'Ardmatrixlab',
   '23000000-0000-0000-0000-000000000003',
   20,
   2,
   'physical',
   'ARDMATRIX',
   'Lab Server',
   'SIM-DEL-ARDMATRIXLAB-001',
   'ARD-LAB-001',
   'x86_64',
   'Ubuntu Linux',
   '24.04',
   'active',
   '10000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000001',
   'server-del-ardmatrixlab',
   true,
   '{"purpose":"hands-on lab","environment":"development"}')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.cpu_devices
  (id, server_id, socket_index, manufacturer, model, architecture,
   physical_cores, logical_processors, base_frequency_mhz, max_frequency_mhz)
VALUES
  ('31000000-0000-0000-0000-000000000004',
   '30000000-0000-0000-0000-000000000004', 0,
   'AMD', 'EPYC Lab CPU', 'x86_64', 16, 32, 2500, 3500)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.memory_modules
  (id, server_id, slot, manufacturer, memory_type, capacity_bytes, speed_mts, ecc)
VALUES
  ('32000000-0000-0000-0000-000000000005',
   '30000000-0000-0000-0000-000000000004', 'A1',
   'Micron', 'DDR5', 34359738368, 4800, true),
  ('32000000-0000-0000-0000-000000000006',
   '30000000-0000-0000-0000-000000000004', 'A2',
   'Micron', 'DDR5', 34359738368, 4800, true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.storage_devices
  (id, server_id, device_name, manufacturer, model, media_type,
   interface_type, capacity_bytes, status)
VALUES
  ('34000000-0000-0000-0000-000000000004',
   '30000000-0000-0000-0000-000000000004', 'nvme0n1',
   'Samsung', 'Lab NVMe', 'nvme', 'PCIe', 2199023255552, 'active')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.network_interfaces
  (id, server_id, interface_name, interface_type, mac_address,
   ip_addresses, mtu, speed_bps, administrative_status)
VALUES
  ('41000000-0000-0000-0000-000000000004',
   '30000000-0000-0000-0000-000000000004', 'eno1', 'ethernet',
   '02:00:00:00:03:04', ARRAY['10.30.10.14'::inet], 1500, 10000000000, 'up')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.inventory_changes
  (entity_type, entity_id, change_type, source_id, is_simulated, current_values)
SELECT
  'server',
  s.id,
  'created',
  s.source_id,
  s.is_simulated,
  jsonb_build_object(
    'server_key', s.server_key,
    'hostname', s.hostname,
    'site', 'dc-delhi',
    'rack', 'rack-a01'
  )
FROM inventory.servers s
WHERE s.server_key = 'srv-del-ardmatrixlab'
  AND NOT EXISTS (
    SELECT 1
    FROM inventory.inventory_changes c
    WHERE c.entity_type = 'server'
      AND c.entity_id = s.id
      AND c.change_type = 'created'
  );

COMMIT;
