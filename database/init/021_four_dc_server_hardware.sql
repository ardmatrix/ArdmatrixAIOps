BEGIN;

-- Normalized physical hardware for the four-DC reference inventory.
INSERT INTO inventory.cpu_devices
  (id,server_id,socket_index,manufacturer,model,architecture,physical_cores,
   logical_processors,base_frequency_mhz,max_frequency_mhz,l3_cache_bytes,numa_node,attributes)
SELECT md5(sv.server_key||'-cpu-'||socket_no)::uuid,sv.id,socket_no-1,
       CASE sv.manufacturer WHEN 'HPE' THEN 'AMD' ELSE 'Intel' END,
       CASE sv.manufacturer WHEN 'HPE' THEN 'EPYC 9354P' ELSE 'Xeon Gold 6448Y' END,
       'x86_64',16,32,2500,4100,67108864,socket_no-1,
       jsonb_build_object('socket',socket_no,'inventory_source','simulated-redfish')
FROM inventory.servers sv CROSS JOIN generate_series(1,2) socket_no
ON CONFLICT (server_id,socket_index) DO UPDATE SET
  model=excluded.model,physical_cores=excluded.physical_cores,
  logical_processors=excluded.logical_processors,attributes=excluded.attributes;

INSERT INTO inventory.memory_modules
  (id,server_id,slot,manufacturer,part_number,serial_number,memory_type,
   capacity_bytes,speed_mts,ecc,attributes)
SELECT md5(sv.server_key||'-dimm-'||dimm_no)::uuid,sv.id,'DIMM-'||lpad(dimm_no::text,2,'0'),
       CASE dimm_no%3 WHEN 0 THEN 'Samsung' WHEN 1 THEN 'Micron' ELSE 'SK hynix' END,
       'DDR5-32G-4800','SIM-'||upper(substr(md5(sv.server_key||'memory'||dimm_no),1,12)),
       'DDR5',34359738368,4800,true,
       jsonb_build_object('channel',ceil(dimm_no/2.0),'inventory_source','simulated-redfish')
FROM inventory.servers sv CROSS JOIN generate_series(1,8) dimm_no
ON CONFLICT (server_id,slot) DO UPDATE SET
  capacity_bytes=excluded.capacity_bytes,speed_mts=excluded.speed_mts,
  memory_type=excluded.memory_type,attributes=excluded.attributes;

INSERT INTO inventory.storage_devices
  (id,server_id,device_name,manufacturer,model,serial_number,media_type,
   interface_type,capacity_bytes,firmware_version,raid_group,status,attributes)
SELECT md5(sv.server_key||'-disk-'||disk_no)::uuid,sv.id,'nvme'||(disk_no-1)||'n1',
       CASE disk_no%2 WHEN 0 THEN 'Samsung' ELSE 'Kioxia' END,
       CASE disk_no%2 WHEN 0 THEN 'PM9A3 1.92TB' ELSE 'CD8-V 1.92TB' END,
       'SIM-'||upper(substr(md5(sv.server_key||'disk'||disk_no),1,12)),
       'nvme','PCIe 4.0 NVMe',2199023255552,'2.1.0','RAID10','active',
       jsonb_build_object('wear_remaining_pct',96-(disk_no%3),'inventory_source','simulated-redfish')
FROM inventory.servers sv CROSS JOIN generate_series(1,4) disk_no
ON CONFLICT (server_id,device_name) DO UPDATE SET
  capacity_bytes=excluded.capacity_bytes,status=excluded.status,
  firmware_version=excluded.firmware_version,attributes=excluded.attributes;

COMMIT;
