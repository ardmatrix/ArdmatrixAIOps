BEGIN;

INSERT INTO inventory.owners (owner_key,name,owner_type,contact_email)
VALUES ('global-infra-ops','Global Infrastructure Operations','team','infra-ops@example.invalid')
ON CONFLICT (owner_key) DO UPDATE SET name=excluded.name;

INSERT INTO inventory.sites
  (id,site_key,name,site_type,status,address,latitude,longitude,timezone,owner_id,source_id,source_native_id,
   is_simulated,region,environment,health_status,facility_power_capacity_kw,facility_power_used_kw,
   cooling_capacity_kw,temperature_c,humidity_pct,pue,monitoring_coverage_pct,inventory_completeness_pct)
VALUES
  (md5('site-dc-hyderabad')::uuid,'dc-hyderabad','Hyderabad DR Data Center','data_center','active',
   '{"city":"Hyderabad","country":"India"}',17.3850,78.4867,'Asia/Kolkata',
   (SELECT id FROM inventory.owners WHERE owner_key='global-infra-ops'),
   (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),'site-hyd',true,
   'South India','disaster_recovery','healthy',420,238,350,22.9,45,1.39,96,94),
  (md5('site-dc-singapore')::uuid,'dc-singapore','Singapore Data Center','data_center','active',
   '{"city":"Singapore","country":"Singapore"}',1.3521,103.8198,'Asia/Singapore',
   (SELECT id FROM inventory.owners WHERE owner_key='global-infra-ops'),
   (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),'site-sin',true,
   'Southeast Asia','production','critical',700,574,590,27.3,61,1.71,78,82)
ON CONFLICT (site_key) DO UPDATE SET
  name=excluded.name,region=excluded.region,environment=excluded.environment,health_status=excluded.health_status,
  facility_power_capacity_kw=excluded.facility_power_capacity_kw,facility_power_used_kw=excluded.facility_power_used_kw,
  cooling_capacity_kw=excluded.cooling_capacity_kw,temperature_c=excluded.temperature_c,humidity_pct=excluded.humidity_pct,
  pue=excluded.pue,monitoring_coverage_pct=excluded.monitoring_coverage_pct,
  inventory_completeness_pct=excluded.inventory_completeness_pct,is_simulated=true,last_seen_at=now();

UPDATE inventory.sites SET
  region = CASE site_key
    WHEN 'dc-mumbai' THEN 'West India' WHEN 'dc-bengaluru' THEN 'South India'
    WHEN 'dc-delhi' THEN 'North India' WHEN 'customer-dc-01' THEN 'South India' ELSE region END,
  environment = CASE WHEN site_key='dc-delhi' THEN 'disaster_recovery' ELSE 'production' END,
  health_status = CASE WHEN site_key='dc-bengaluru' THEN 'warning' WHEN site_key='dc-delhi' THEN 'warning' ELSE health_status END,
  facility_power_capacity_kw = coalesce(facility_power_capacity_kw,450),
  facility_power_used_kw = coalesce(facility_power_used_kw,280),cooling_capacity_kw=coalesce(cooling_capacity_kw,380),
  temperature_c=coalesce(temperature_c,23.5),humidity_pct=coalesce(humidity_pct,47),pue=coalesce(pue,1.45),
  monitoring_coverage_pct=coalesce(monitoring_coverage_pct,95),inventory_completeness_pct=coalesce(inventory_completeness_pct,93),
  last_seen_at=now(),is_simulated=CASE WHEN site_key='customer-dc-01' THEN false ELSE true END;

INSERT INTO inventory.rooms (id,site_id,room_key,name,floor,status,is_simulated)
SELECT md5('tech-room-'||s.site_key)::uuid,s.id,'tech-hall','Technical Hall','Ground','active',s.is_simulated
FROM inventory.sites s
ON CONFLICT (site_id,room_key) DO UPDATE SET name=excluded.name,status='active';

INSERT INTO inventory.data_center_rows (id,room_id,row_key,name,is_simulated)
SELECT md5('tech-row-'||s.site_key)::uuid,rm.id,'tech-row','Technical Row',s.is_simulated
FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id AND rm.room_key='tech-hall'
ON CONFLICT (room_id,row_key) DO UPDATE SET name=excluded.name;

INSERT INTO inventory.racks
  (id,row_id,rack_key,name,rack_units,max_power_watts,status,is_simulated,health_status,used_rack_units,
   current_power_watts,temperature_c,humidity_pct,monitoring_status)
SELECT md5('tech-rack-'||s.site_key||'-'||g)::uuid,dr.id,'tech-rack-'||lpad(g::text,2,'0'),
       upper(replace(s.site_key,'dc-',''))||'-R'||lpad(g::text,2,'0'),42,12000,'active',s.is_simulated,
       CASE WHEN (g+length(s.site_key))%11=0 THEN 'critical' WHEN (g+length(s.site_key))%5=0 THEN 'warning' ELSE 'healthy' END,
       20+((g*5+length(s.site_key))%20),5200+((g*1300+length(s.site_key)*100)%6200),
       21+((g*7+length(s.site_key))%70)/10.0,40+((g*3+length(s.site_key))%20),
       CASE WHEN (g+length(s.site_key))%13=0 THEN 'unmonitored' ELSE 'monitored' END
FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id AND rm.room_key='tech-hall'
JOIN inventory.data_center_rows dr ON dr.room_id=rm.id AND dr.row_key='tech-row'
CROSS JOIN generate_series(1,4) g
ON CONFLICT (row_id,rack_key) DO UPDATE SET health_status=excluded.health_status,
 used_rack_units=excluded.used_rack_units,current_power_watts=excluded.current_power_watts,
 temperature_c=excluded.temperature_c,humidity_pct=excluded.humidity_pct,monitoring_status=excluded.monitoring_status;

INSERT INTO inventory.servers
  (id,server_key,hostname,rack_id,rack_unit_start,rack_unit_height,server_type,manufacturer,model,serial_number,
   asset_tag,architecture,operating_system,operating_system_version,status,owner_id,source_id,source_native_id,
   is_simulated,health_status,environment,criticality,monitoring_status,warranty_expiry,end_of_support,business_service)
SELECT md5('tech-server-'||s.site_key||'-'||r.rack_key||'-'||g)::uuid,
       'tech-srv-'||replace(s.site_key,'dc-','')||'-'||right(r.rack_key,2)||'-'||lpad(g::text,2,'0'),
       'srv-'||replace(s.site_key,'dc-','')||'-'||right(r.rack_key,2)||'-'||lpad(g::text,2,'0'),r.id,2+(g-1)*6,2,
       'physical',CASE g%3 WHEN 0 THEN 'Dell' WHEN 1 THEN 'HPE' ELSE 'Lenovo' END,
       CASE g%3 WHEN 0 THEN 'PowerEdge R760' WHEN 1 THEN 'ProLiant DL380 Gen11' ELSE 'ThinkSystem SR650 V3' END,
       'SIM-'||upper(substr(md5(s.site_key||r.rack_key||g),1,12)),'TECH-'||upper(substr(md5(r.rack_key||g),1,10)),
       'x86_64',CASE g%3 WHEN 0 THEN 'Ubuntu Linux' WHEN 1 THEN 'Red Hat Enterprise Linux' ELSE 'VMware ESXi' END,
       CASE g%3 WHEN 1 THEN '9.4' ELSE '24.04' END,
       CASE WHEN (g+length(r.name))%19=0 THEN 'failed' WHEN (g+length(r.name))%9=0 THEN 'maintenance' ELSE 'active' END,
       coalesce(s.owner_id,(SELECT id FROM inventory.owners WHERE owner_key='global-infra-ops')),
       (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),
       'tech-'||s.site_key||'-'||r.rack_key||'-'||g,true,
       CASE WHEN (g+length(r.name))%19=0 THEN 'critical' WHEN (g+length(r.name))%7=0 THEN 'warning' ELSE 'healthy' END,
       s.environment,CASE g%4 WHEN 0 THEN 'critical' WHEN 1 THEN 'high' WHEN 2 THEN 'medium' ELSE 'low' END,
       CASE WHEN (g+length(r.name))%17=0 THEN 'unmonitored' ELSE 'monitored' END,
       current_date+(180+(g*120))::int,current_date+(540+(g*180))::int,
       CASE g%3 WHEN 0 THEN 'CRM' WHEN 1 THEN 'Payments' ELSE 'Analytics' END
FROM inventory.racks r JOIN inventory.data_center_rows dr ON dr.id=r.row_id
JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
CROSS JOIN generate_series(1,6) g WHERE r.rack_key LIKE 'tech-rack-%'
ON CONFLICT (server_key) DO UPDATE SET health_status=excluded.health_status,status=excluded.status,
 monitoring_status=excluded.monitoring_status,last_seen_at=now();

INSERT INTO inventory.cpu_devices
  (id,server_id,socket_index,manufacturer,model,architecture,physical_cores,logical_processors,base_frequency_mhz,max_frequency_mhz)
SELECT md5('cpu-'||sv.server_key)::uuid,sv.id,0,'Intel','Xeon Gold 6448Y','x86_64',32,64,2100,4100
FROM inventory.servers sv WHERE sv.server_key LIKE 'tech-srv-%'
ON CONFLICT (server_id,socket_index) DO NOTHING;

INSERT INTO inventory.memory_modules
  (id,server_id,slot,manufacturer,memory_type,capacity_bytes,speed_mts,ecc)
SELECT md5('memory-'||sv.server_key)::uuid,sv.id,'A1','Samsung','DDR5',137438953472,4800,true
FROM inventory.servers sv WHERE sv.server_key LIKE 'tech-srv-%'
ON CONFLICT (server_id,slot) DO NOTHING;

INSERT INTO inventory.storage_devices
  (id,server_id,device_name,manufacturer,model,media_type,interface_type,capacity_bytes,status)
SELECT md5('storage-'||sv.server_key)::uuid,sv.id,'nvme0n1','Samsung','PM9A3','nvme','PCIe',3840755982336,'active'
FROM inventory.servers sv WHERE sv.server_key LIKE 'tech-srv-%'
ON CONFLICT (server_id,device_name) DO NOTHING;

INSERT INTO inventory.hypervisors
  (id,hypervisor_key,server_id,hypervisor_type,version,cluster_name,status,source_id,is_simulated)
SELECT md5('hypervisor-'||sv.server_key)::uuid,'hv-'||sv.server_key,sv.id,'VMware ESXi','8.0 U3',
       upper(replace(s.site_key,'dc-',''))||'-COMPUTE','active',
       (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),true
FROM inventory.servers sv JOIN inventory.racks r ON r.id=sv.rack_id
JOIN inventory.data_center_rows dr ON dr.id=r.row_id JOIN inventory.rooms rm ON rm.id=dr.room_id
JOIN inventory.sites s ON s.id=rm.site_id WHERE sv.server_key LIKE 'tech-srv-%'
ON CONFLICT (hypervisor_key) DO UPDATE SET status=excluded.status;

INSERT INTO inventory.virtual_machines
  (id,vm_key,name,hostname,hypervisor_id,vcpu_count,memory_bytes,provisioned_storage_bytes,operating_system,
   operating_system_version,ip_addresses,status,owner_id,source_id,source_native_id,is_simulated,
   health_status,environment,criticality,monitoring_status,cpu_utilization_pct,memory_utilization_pct,
   storage_utilization_pct,uptime_pct,snapshot_count,backup_status)
SELECT md5('vm-'||sv.server_key||'-'||g)::uuid,'tech-vm-'||sv.server_key||'-'||g,
       upper(replace(s.site_key,'dc-',''))||' Workload VM '||right(sv.server_key,5)||'-'||g,
       'vm-'||right(sv.server_key,9)||'-'||g,h.id,2+(g%4)*2,(8+g*8)::bigint*1073741824,
       (100+g*100)::bigint*1073741824,CASE g%3 WHEN 0 THEN 'Windows Server' WHEN 1 THEN 'Ubuntu Linux' ELSE 'Rocky Linux' END,
       CASE g%3 WHEN 0 THEN '2025' WHEN 1 THEN '24.04' ELSE '9.4' END,'{}',
       CASE WHEN (g+length(sv.server_key))%23=0 THEN 'failed' WHEN (g+length(sv.server_key))%11=0 THEN 'stopped' ELSE 'running' END,
       sv.owner_id,(SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),
       'tech-vm-'||sv.server_key||'-'||g,true,
       CASE WHEN (g+length(sv.server_key))%23=0 THEN 'critical' WHEN (g+length(sv.server_key))%8=0 THEN 'warning' ELSE 'healthy' END,
       sv.environment,sv.criticality,CASE WHEN (g+length(sv.server_key))%29=0 THEN 'unmonitored' ELSE 'monitored' END,
       25+((g*17+length(sv.server_key))%68),30+((g*13+length(sv.server_key))%65),
       35+((g*11+length(sv.server_key))%60),99.5+((g*7)%50)/100.0,g%4,
       CASE WHEN g%13=0 THEN 'failed' WHEN g%7=0 THEN 'warning' ELSE 'protected' END
FROM inventory.servers sv JOIN inventory.hypervisors h ON h.server_id=sv.id
JOIN inventory.racks r ON r.id=sv.rack_id JOIN inventory.data_center_rows dr ON dr.id=r.row_id
JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
CROSS JOIN generate_series(1,3) g WHERE sv.server_key LIKE 'tech-srv-%'
ON CONFLICT (vm_key) DO UPDATE SET health_status=excluded.health_status,status=excluded.status,
 cpu_utilization_pct=excluded.cpu_utilization_pct,memory_utilization_pct=excluded.memory_utilization_pct,
 storage_utilization_pct=excluded.storage_utilization_pct,last_seen_at=now();

INSERT INTO events.inventory_alerts
  (alert_key,entity_type,entity_id,severity,status,title,description,metric_name,metric_value,threshold_value,is_simulated)
SELECT 'alert-server-'||sv.server_key,'server',sv.id,
       CASE sv.health_status WHEN 'critical' THEN 'critical' ELSE 'warning' END,'open',
       CASE sv.health_status WHEN 'critical' THEN 'Server availability failure' ELSE 'Server health degradation' END,
       'Deterministic simulated condition for dashboard demonstration','health_score',
       CASE sv.health_status WHEN 'critical' THEN 20 ELSE 65 END,75,true
FROM inventory.servers sv WHERE sv.server_key LIKE 'tech-srv-%' AND sv.health_status<>'healthy'
ON CONFLICT (alert_key) DO UPDATE SET severity=excluded.severity,status='open',opened_at=now();

INSERT INTO events.inventory_alerts
  (alert_key,entity_type,entity_id,severity,status,title,description,metric_name,metric_value,threshold_value,is_simulated)
SELECT 'alert-vm-'||vm.vm_key,'vm',vm.id,
       CASE vm.health_status WHEN 'critical' THEN 'critical' ELSE 'warning' END,'open',
       'Virtual machine resource pressure','Simulated VM utilization exceeded its operating baseline',
       'resource_utilization_pct',greatest(vm.cpu_utilization_pct,vm.memory_utilization_pct,vm.storage_utilization_pct),80,true
FROM inventory.virtual_machines vm WHERE vm.vm_key LIKE 'tech-vm-%' AND vm.health_status<>'healthy'
ON CONFLICT (alert_key) DO UPDATE SET severity=excluded.severity,status='open',opened_at=now();

COMMIT;
