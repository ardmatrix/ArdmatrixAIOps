BEGIN;

CREATE TABLE IF NOT EXISTS inventory.network_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    link_key text NOT NULL UNIQUE,
    source_device_id uuid NOT NULL REFERENCES inventory.network_devices(id) ON DELETE CASCADE,
    source_interface text NOT NULL,
    target_device_id uuid REFERENCES inventory.network_devices(id) ON DELETE CASCADE,
    target_interface text,
    link_type text NOT NULL CHECK (link_type IN ('access','trunk','port_channel','wan','internet','management')),
    provider text,
    circuit_id text,
    bandwidth_bps bigint NOT NULL CHECK (bandwidth_bps > 0),
    utilization_pct numeric(5,2) NOT NULL DEFAULT 0 CHECK (utilization_pct BETWEEN 0 AND 100),
    latency_ms numeric(8,2) NOT NULL DEFAULT 0 CHECK (latency_ms >= 0),
    packet_loss_pct numeric(6,3) NOT NULL DEFAULT 0 CHECK (packet_loss_pct BETWEEN 0 AND 100),
    status text NOT NULL CHECK (status IN ('up','degraded','down','maintenance','unknown')),
    redundancy_group text,
    is_simulated boolean NOT NULL DEFAULT false,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory.network_vlans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vlan_key text NOT NULL UNIQUE,
    site_id uuid NOT NULL REFERENCES inventory.sites(id) ON DELETE CASCADE,
    vlan_id integer NOT NULL CHECK (vlan_id BETWEEN 1 AND 4094),
    name text NOT NULL,
    purpose text NOT NULL,
    vrf_name text NOT NULL,
    cidr cidr NOT NULL,
    gateway inet,
    allocated_addresses integer NOT NULL DEFAULT 0,
    capacity_addresses integer NOT NULL DEFAULT 254,
    status text NOT NULL CHECK (status IN ('active','degraded','reserved','retired')),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id,vlan_id)
);

CREATE TABLE IF NOT EXISTS inventory.network_vrfs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vrf_key text NOT NULL UNIQUE,
    site_id uuid NOT NULL REFERENCES inventory.sites(id) ON DELETE CASCADE,
    name text NOT NULL,
    route_distinguisher text,
    route_count integer NOT NULL DEFAULT 0,
    bgp_neighbor_count integer NOT NULL DEFAULT 0,
    bgp_neighbors_up integer NOT NULL DEFAULT 0,
    status text NOT NULL CHECK (status IN ('active','degraded','down','maintenance')),
    is_simulated boolean NOT NULL DEFAULT false,
    last_converged_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id,name)
);

CREATE TABLE IF NOT EXISTS inventory.network_circuits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    circuit_key text NOT NULL UNIQUE,
    site_id uuid NOT NULL REFERENCES inventory.sites(id) ON DELETE CASCADE,
    provider text NOT NULL,
    service_type text NOT NULL CHECK (service_type IN ('mpls','internet','sdwan','dark_fiber','cloud_connect')),
    provider_circuit_id text NOT NULL,
    bandwidth_bps bigint NOT NULL CHECK (bandwidth_bps > 0),
    committed_bps bigint NOT NULL CHECK (committed_bps > 0),
    utilization_pct numeric(5,2) NOT NULL CHECK (utilization_pct BETWEEN 0 AND 100),
    latency_ms numeric(8,2) NOT NULL CHECK (latency_ms >= 0),
    packet_loss_pct numeric(6,3) NOT NULL CHECK (packet_loss_pct BETWEEN 0 AND 100),
    availability_pct numeric(7,4) NOT NULL CHECK (availability_pct BETWEEN 0 AND 100),
    status text NOT NULL CHECK (status IN ('up','degraded','down','maintenance')),
    redundancy_role text NOT NULL CHECK (redundancy_role IN ('primary','secondary')),
    is_simulated boolean NOT NULL DEFAULT false,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

WITH site_racks AS (
  SELECT s.id site_id,s.site_key,r.id rack_id,
         dense_rank() OVER (ORDER BY s.site_key) site_no
  FROM inventory.sites s
  JOIN LATERAL (
    SELECT r.id FROM inventory.racks r
    JOIN inventory.data_center_rows dr ON dr.id=r.row_id
    JOIN inventory.rooms rm ON rm.id=dr.room_id
    WHERE rm.site_id=s.id ORDER BY r.rack_key LIMIT 1
  ) r ON true
), devices AS (
  SELECT sr.*,x.role,x.device_type,x.offset_no,x.vendor,x.model FROM site_racks sr
  CROSS JOIN (VALUES
    ('core-01','switch',10,'Cisco','Nexus 9364C'),
    ('core-02','switch',11,'Cisco','Nexus 9364C'),
    ('edge-fw-01','firewall',12,'Palo Alto Networks','PA-5450'),
    ('adc-01','load_balancer',13,'F5','BIG-IP i5800')
  ) x(role,device_type,offset_no,vendor,model)
)
INSERT INTO inventory.network_devices
  (device_key,hostname,rack_id,device_type,role,manufacturer,model,serial_number,operating_system,
   operating_system_version,management_address,status,is_simulated,attributes,last_seen_at)
SELECT site_key||'-'||role,site_key||'-'||role,rack_id,device_type,role,vendor,model,
       'SIM-'||upper(replace(site_key,'-',''))||'-'||offset_no,
       CASE WHEN device_type='switch' THEN 'NX-OS' WHEN device_type='firewall' THEN 'PAN-OS' ELSE 'TMOS' END,
       CASE WHEN device_type='switch' THEN '10.4(2)' WHEN device_type='firewall' THEN '11.1.4' ELSE '17.1.1' END,
       format('10.%s.0.%s',site_no+40,offset_no)::inet,
       CASE WHEN site_key='dc-singapore' AND role='core-02' THEN 'maintenance' ELSE 'active' END,true,
       jsonb_build_object('monitoring_status','monitored','ha_role',CASE WHEN role='core-01' THEN 'active' WHEN role='core-02' THEN 'standby' ELSE 'active-active' END,
                          'firmware_compliance',CASE WHEN site_key='dc-delhi' AND role='edge-fw-01' THEN 'upgrade_required' ELSE 'compliant' END,
                          'config_backup',CASE WHEN site_key='dc-bengaluru' AND role='adc-01' THEN 'stale' ELSE 'current' END,
                          'cpu_utilization_pct',20+site_no*4+offset_no%5,'memory_utilization_pct',35+site_no*3,
                          'temperature_c',29+site_no,'open_alerts',CASE WHEN site_key='dc-delhi' AND role='edge-fw-01' THEN 3 WHEN site_key='dc-singapore' AND role='core-02' THEN 2 ELSE 0 END),
       now()-make_interval(mins => (site_no*2)::integer)
FROM devices
ON CONFLICT (device_key) DO UPDATE SET attributes=EXCLUDED.attributes,status=EXCLUDED.status,last_seen_at=EXCLUDED.last_seen_at,updated_at=now();

INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,iface.name,'ethernet',CASE WHEN iface.name='Management0' THEN ARRAY[nd.management_address] ELSE '{}'::inet[] END,
       CASE WHEN iface.name='Management0' THEN 1500 ELSE 9216 END,iface.speed,
       CASE WHEN nd.status='maintenance' AND iface.name='Ethernet1/49' THEN 'down' ELSE 'up' END,
       jsonb_build_object('description',iface.description,'operational_status',CASE WHEN nd.status='maintenance' AND iface.name='Ethernet1/49' THEN 'down' ELSE 'up' END,
                          'rx_utilization_pct',(abs(hashtext(nd.device_key||iface.name))%7200)/100.0,
                          'tx_utilization_pct',(abs(hashtext(iface.name||nd.device_key))%6800)/100.0,
                          'errors',abs(hashtext(nd.device_key||iface.name))%12)
FROM inventory.network_devices nd
CROSS JOIN (VALUES ('Management0',1000000000::bigint,'Out-of-band management'),('Ethernet1/49',100000000000::bigint,'Fabric uplink A'),('Ethernet1/50',100000000000::bigint,'Fabric uplink B'),('Port-Channel10',200000000000::bigint,'MLAG peer link')) iface(name,speed,description)
WHERE nd.is_simulated AND (nd.device_key LIKE '%-core-%' OR nd.device_key LIKE '%-edge-fw-%' OR nd.device_key LIKE '%-adc-%')
ON CONFLICT DO NOTHING;

WITH numbered_sites AS (SELECT id,site_key,dense_rank() OVER (ORDER BY site_key) n FROM inventory.sites)
INSERT INTO inventory.network_vlans
  (vlan_key,site_id,vlan_id,name,purpose,vrf_name,cidr,gateway,allocated_addresses,capacity_addresses,status,is_simulated)
SELECT s.site_key||'-vlan-'||v.vlan_id,s.id,v.vlan_id,v.name,v.purpose,v.vrf,
       format('10.%s.%s.0/24',s.n+40,v.octet)::cidr,format('10.%s.%s.1',s.n+40,v.octet)::inet,
       35+s.n*11+v.octet,254,CASE WHEN s.site_key='dc-delhi' AND v.vlan_id=130 THEN 'degraded' ELSE 'active' END,true
FROM numbered_sites s CROSS JOIN (VALUES (110,'Production Servers','server','PROD',10),(120,'Virtualization','hypervisor','PROD',20),(130,'Kubernetes','container','PROD',30),(199,'Management','management','MGMT',99)) v(vlan_id,name,purpose,vrf,octet)
ON CONFLICT (vlan_key) DO UPDATE SET allocated_addresses=EXCLUDED.allocated_addresses,status=EXCLUDED.status,updated_at=now();

WITH numbered_sites AS (SELECT id,site_key,dense_rank() OVER (ORDER BY site_key) n FROM inventory.sites)
INSERT INTO inventory.network_vrfs
  (vrf_key,site_id,name,route_distinguisher,route_count,bgp_neighbor_count,bgp_neighbors_up,status,is_simulated,last_converged_at)
SELECT s.site_key||'-'||lower(v.name),s.id,v.name,format('65000:%s',s.n*10+v.o),180+s.n*37+v.o*25,4,
       CASE WHEN s.site_key='dc-delhi' AND v.name='PROD' THEN 3 ELSE 4 END,
       CASE WHEN s.site_key='dc-delhi' AND v.name='PROD' THEN 'degraded' ELSE 'active' END,true,now()-make_interval(mins=>(s.n*3)::integer)
FROM numbered_sites s CROSS JOIN (VALUES ('PROD',1),('MGMT',2)) v(name,o)
ON CONFLICT (vrf_key) DO UPDATE SET route_count=EXCLUDED.route_count,bgp_neighbors_up=EXCLUDED.bgp_neighbors_up,status=EXCLUDED.status,updated_at=now();

WITH numbered_sites AS (SELECT id,site_key,dense_rank() OVER (ORDER BY site_key) n FROM inventory.sites)
INSERT INTO inventory.network_circuits
  (circuit_key,site_id,provider,service_type,provider_circuit_id,bandwidth_bps,committed_bps,utilization_pct,latency_ms,packet_loss_pct,availability_pct,status,redundancy_role,is_simulated,last_seen_at)
SELECT s.site_key||'-'||lower(c.role)||'-wan',s.id,c.provider,c.service_type,
       upper(substr(replace(s.site_key,'-',''),1,8))||'-'||s.n||c.o, c.bandwidth,c.bandwidth,
       CASE WHEN s.site_key='dc-delhi' AND c.role='primary' THEN 88.4 ELSE 32+s.n*5+c.o*3 END,
       CASE WHEN c.service_type='internet' THEN 22+s.n*2 ELSE 9+s.n END,
       CASE WHEN s.site_key='dc-delhi' AND c.role='primary' THEN 1.85 ELSE 0.01*s.n END,
       CASE WHEN s.site_key='dc-delhi' AND c.role='primary' THEN 98.7500 ELSE 99.9900 END,
       CASE WHEN s.site_key='dc-delhi' AND c.role='primary' THEN 'degraded' ELSE 'up' END,c.role,true,now()-make_interval(mins=>s.n::integer)
FROM numbered_sites s CROSS JOIN (VALUES ('primary','Airtel','mpls',1,10000000000::bigint),('secondary','Tata Communications','sdwan',2,5000000000::bigint)) c(role,provider,service_type,o,bandwidth)
ON CONFLICT (circuit_key) DO UPDATE SET utilization_pct=EXCLUDED.utilization_pct,latency_ms=EXCLUDED.latency_ms,packet_loss_pct=EXCLUDED.packet_loss_pct,availability_pct=EXCLUDED.availability_pct,status=EXCLUDED.status,updated_at=now();

WITH pairs AS (
 SELECT s.site_key,c1.id core1,c2.id core2,fw.id firewall,adc.id adc
 FROM inventory.sites s
 JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01'
 JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02'
 JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
 JOIN inventory.network_devices adc ON adc.device_key=s.site_key||'-adc-01'
), link_rows AS (
 SELECT site_key||'-core-peer' link_key,core1 src,'Port-Channel10' src_if,core2 dst,'Port-Channel10' dst_if,'port_channel' type,200000000000::bigint bw,site_key||'-fabric' rg FROM pairs
 UNION ALL SELECT site_key||'-core1-fw',core1,'Ethernet1/49',firewall,'Ethernet1/49','trunk',100000000000,site_key||'-edge' FROM pairs
 UNION ALL SELECT site_key||'-core2-fw',core2,'Ethernet1/49',firewall,'Ethernet1/50','trunk',100000000000,site_key||'-edge' FROM pairs
 UNION ALL SELECT site_key||'-core1-adc',core1,'Ethernet1/50',adc,'Ethernet1/49','trunk',100000000000,site_key||'-services' FROM pairs
 UNION ALL SELECT site_key||'-core2-adc',core2,'Ethernet1/50',adc,'Ethernet1/50','trunk',100000000000,site_key||'-services' FROM pairs
)
INSERT INTO inventory.network_links
  (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,bandwidth_bps,utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,last_seen_at)
SELECT link_key,src,src_if,dst,dst_if,type,bw,(abs(hashtext(link_key))%7000)/100.0,
       (abs(hashtext(link_key))%80)/100.0,(abs(hashtext(reverse(link_key)))%20)/1000.0,
       CASE WHEN link_key='dc-delhi-core2-fw' THEN 'degraded' WHEN link_key='dc-singapore-core-peer' THEN 'maintenance' ELSE 'up' END,
       rg,true,now()-interval '2 minutes' FROM link_rows
ON CONFLICT (link_key) DO UPDATE SET utilization_pct=EXCLUDED.utilization_pct,status=EXCLUDED.status,last_seen_at=EXCLUDED.last_seen_at,updated_at=now();

CREATE OR REPLACE VIEW inventory.network_device_operational_overview AS
SELECT s.site_key,s.name site_name,r.rack_key,r.name rack_name,nd.device_key,nd.hostname,nd.device_type,nd.role,
       nd.manufacturer,nd.model,nd.operating_system,nd.operating_system_version,nd.management_address,nd.status,
       coalesce(nd.attributes->>'ha_role','standalone') ha_role,
       coalesce(nd.attributes->>'monitoring_status','unknown') monitoring_status,
       coalesce(nd.attributes->>'firmware_compliance','unknown') firmware_compliance,
       coalesce(nd.attributes->>'config_backup','unknown') config_backup,
       coalesce((nd.attributes->>'cpu_utilization_pct')::numeric,0) cpu_utilization_pct,
       coalesce((nd.attributes->>'memory_utilization_pct')::numeric,0) memory_utilization_pct,
       coalesce((nd.attributes->>'temperature_c')::numeric,0) temperature_c,
       coalesce((nd.attributes->>'open_alerts')::integer,0) open_alerts,
       count(DISTINCT ni.id) interface_count,count(DISTINCT nl.id) link_count,
       nd.last_seen_at,nd.is_simulated
FROM inventory.network_devices nd
LEFT JOIN inventory.racks r ON r.id=nd.rack_id
LEFT JOIN inventory.data_center_rows dr ON dr.id=r.row_id
LEFT JOIN inventory.rooms rm ON rm.id=dr.room_id
LEFT JOIN inventory.sites s ON s.id=rm.site_id
LEFT JOIN inventory.network_interfaces ni ON ni.network_device_id=nd.id
LEFT JOIN inventory.network_links nl ON nl.source_device_id=nd.id OR nl.target_device_id=nd.id
GROUP BY s.site_key,s.name,r.rack_key,r.name,nd.id;

CREATE INDEX IF NOT EXISTS network_links_source_idx ON inventory.network_links(source_device_id);
CREATE INDEX IF NOT EXISTS network_links_target_idx ON inventory.network_links(target_device_id);
CREATE INDEX IF NOT EXISTS network_circuits_site_idx ON inventory.network_circuits(site_id);
CREATE INDEX IF NOT EXISTS network_vlans_site_idx ON inventory.network_vlans(site_id);

COMMIT;
