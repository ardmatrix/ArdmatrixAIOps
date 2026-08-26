BEGIN;

CREATE TABLE IF NOT EXISTS inventory.server_network_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attachment_key text NOT NULL UNIQUE,
  site_id uuid NOT NULL REFERENCES inventory.sites(id) ON DELETE CASCADE,
  server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
  server_interface_id uuid NOT NULL REFERENCES inventory.network_interfaces(id) ON DELETE CASCADE,
  switch_device_id uuid NOT NULL REFERENCES inventory.network_devices(id) ON DELETE CASCADE,
  switch_interface_id uuid NOT NULL REFERENCES inventory.network_interfaces(id) ON DELETE CASCADE,
  vlan_id uuid REFERENCES inventory.network_vlans(id),
  connection_type text NOT NULL DEFAULT 'ethernet' CHECK (connection_type IN ('ethernet','fiber','bond','virtual')),
  status text NOT NULL DEFAULT 'up' CHECK (status IN ('up','degraded','down','maintenance','unknown')),
  redundancy_role text NOT NULL DEFAULT 'primary' CHECK (redundancy_role IN ('primary','secondary')),
  is_simulated boolean NOT NULL DEFAULT false,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Two access switches per data center provide realistic server-port density and redundancy.
WITH site_racks AS (
  SELECT s.id site_id,s.site_key,r.id rack_id,dense_rank() OVER (ORDER BY s.site_key) site_no
  FROM inventory.sites s
  JOIN LATERAL (
    SELECT r.id FROM inventory.racks r
    JOIN inventory.data_center_rows dr ON dr.id=r.row_id
    JOIN inventory.rooms rm ON rm.id=dr.room_id
    WHERE rm.site_id=s.id ORDER BY r.rack_key LIMIT 1
  ) r ON true
)
INSERT INTO inventory.network_devices
  (device_key,hostname,rack_id,device_type,role,manufacturer,model,serial_number,operating_system,
   operating_system_version,management_address,status,is_simulated,attributes,last_seen_at)
SELECT sr.site_key||'-access-'||lpad(g::text,2,'0'),sr.site_key||'-access-'||lpad(g::text,2,'0'),sr.rack_id,
       'switch','access','Cisco','Nexus 93180YC-FX3','SIM-'||upper(replace(sr.site_key,'-',''))||'-ACC'||g,
       'NX-OS','10.4(2)',format('10.%s.0.%s',sr.site_no+40,30+g)::inet,'active',true,
       jsonb_build_object('switching_layer','L2/L3 access','monitoring_status','monitored','ha_role','peer',
                          'firmware_compliance','compliant','config_backup','current','cpu_utilization_pct',18+sr.site_no*2+g,
                          'memory_utilization_pct',31+sr.site_no*2,'temperature_c',28+sr.site_no,'open_alerts',0),
       now()-make_interval(mins=>(sr.site_no+g)::integer)
FROM site_racks sr CROSS JOIN generate_series(1,2) g
ON CONFLICT (device_key) DO UPDATE SET attributes=excluded.attributes,status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Access-switch management and redundant fabric uplinks.
INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,i.name,'ethernet',CASE WHEN i.name='Management0' THEN ARRAY[nd.management_address] ELSE '{}'::inet[] END,
       CASE WHEN i.name='Management0' THEN 1500 ELSE 9216 END,i.speed,'up',
       jsonb_build_object('description',i.description,'operational_status','up','layer',CASE WHEN i.name='Management0' THEN 3 ELSE 2 END,
                          'rx_utilization_pct',(abs(hashtext(nd.device_key||i.name))%4800)/100.0,
                          'tx_utilization_pct',(abs(hashtext(i.name||nd.device_key))%4500)/100.0,'errors',0)
FROM inventory.network_devices nd
CROSS JOIN (VALUES ('Management0',1000000000::bigint,'Out-of-band management'),
                   ('Ethernet1/49',100000000000::bigint,'Uplink to core-01'),
                   ('Ethernet1/50',100000000000::bigint,'Uplink to core-02')) i(name,speed,description)
WHERE nd.device_key LIKE '%-access-01' OR nd.device_key LIKE '%-access-02'
ON CONFLICT DO NOTHING;

WITH server_numbering AS (
  SELECT s.id site_id,s.site_key,sv.id server_id,sv.server_key,
         row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) rn,
         dense_rank() OVER (ORDER BY s.site_key) site_no
  FROM inventory.sites s
  JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
  JOIN inventory.racks r ON r.row_id=dr.id
  JOIN inventory.servers sv ON sv.rack_id=r.id
)
INSERT INTO inventory.network_interfaces
  (server_id,interface_name,interface_type,mac_address,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT sn.server_id,'ens192','ethernet',format('02:%s:%s:%s:%s:%s',substr(md5(sn.server_key),1,2),substr(md5(sn.server_key),3,2),substr(md5(sn.server_key),5,2),substr(md5(sn.server_key),7,2),substr(md5(sn.server_key),9,2))::macaddr,
       ARRAY[format('10.%s.10.%s/24',sn.site_no+40,20+sn.rn)::inet],1500,
       10000000000,'up',jsonb_build_object('description','Primary production network adapter','operational_status','up',
       'layer',3,'rx_utilization_pct',(abs(hashtext(sn.server_key))%6500)/100.0,
       'tx_utilization_pct',(abs(hashtext(reverse(sn.server_key)))%6200)/100.0,'errors',abs(hashtext(sn.server_key))%3)
FROM server_numbering sn
ON CONFLICT DO NOTHING;

UPDATE inventory.network_interfaces ni
SET mac_address=format('02:%s:%s:%s:%s:%s',substr(md5(sv.server_key),1,2),substr(md5(sv.server_key),3,2),
                       substr(md5(sv.server_key),5,2),substr(md5(sv.server_key),7,2),substr(md5(sv.server_key),9,2))::macaddr,
    updated_at=now()
FROM inventory.servers sv
WHERE ni.server_id=sv.id AND ni.interface_name='ens192' AND ni.mac_address IS NULL;

-- Create the exact access-switch front-panel port assigned to every server.
WITH server_numbering AS (
  SELECT s.id site_id,s.site_key,sv.id server_id,sv.server_key,
         row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) rn
  FROM inventory.sites s
  JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
  JOIN inventory.racks r ON r.row_id=dr.id
  JOIN inventory.servers sv ON sv.rack_id=r.id
)
INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT sw.id,'Ethernet1/1/'||ceil(sn.rn/2.0)::integer,'ethernet','{}'::inet[],1500,10000000000,'up',
       jsonb_build_object('description','Server access port · '||sn.server_key,'operational_status','up','layer',2,
                          'mode','access','access_vlan',110,'rx_utilization_pct',(abs(hashtext(sn.server_key||'rx'))%6500)/100.0,
                          'tx_utilization_pct',(abs(hashtext(sn.server_key||'tx'))%6200)/100.0,'errors',abs(hashtext(sn.server_key))%3)
FROM server_numbering sn
JOIN inventory.network_devices sw ON sw.device_key=sn.site_key||'-access-'||lpad((1+(sn.rn-1)%2)::text,2,'0')
ON CONFLICT DO NOTHING;

WITH server_numbering AS (
  SELECT s.id site_id,s.site_key,sv.id server_id,sv.server_key,
         row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) rn
  FROM inventory.sites s
  JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
  JOIN inventory.racks r ON r.row_id=dr.id
  JOIN inventory.servers sv ON sv.rack_id=r.id
)
INSERT INTO inventory.server_network_attachments
  (attachment_key,site_id,server_id,server_interface_id,switch_device_id,switch_interface_id,vlan_id,
   connection_type,status,redundancy_role,is_simulated,attributes,last_seen_at)
SELECT sn.server_key||':ens192:'||sw.device_key||':'||swi.interface_name,sn.site_id,sn.server_id,sni.id,sw.id,swi.id,v.id,
       'ethernet',CASE WHEN sv.status='failed' THEN 'down' WHEN sv.status='maintenance' THEN 'maintenance' ELSE 'up' END,
       'primary',true,jsonb_build_object('native_vlan',110,'port_mode','access','discovery_method','simulated-lldp'),
       now()-interval '1 minute'
FROM server_numbering sn
JOIN inventory.servers sv ON sv.id=sn.server_id
JOIN inventory.network_interfaces sni ON sni.server_id=sn.server_id AND sni.interface_name='ens192'
JOIN inventory.network_devices sw ON sw.device_key=sn.site_key||'-access-'||lpad((1+(sn.rn-1)%2)::text,2,'0')
JOIN inventory.network_interfaces swi ON swi.network_device_id=sw.id AND swi.interface_name='Ethernet1/1/'||ceil(sn.rn/2.0)::integer
JOIN inventory.network_vlans v ON v.site_id=sn.site_id AND v.vlan_id=110
ON CONFLICT (attachment_key) DO UPDATE SET status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Access-switch uplinks to both core switches.
WITH pairs AS (
  SELECT s.site_key,a.id access_device,c1.id core1,c2.id core2,a.device_key
  FROM inventory.sites s
  JOIN inventory.network_devices a ON a.device_key IN (s.site_key||'-access-01',s.site_key||'-access-02')
  JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01'
  JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02'
), links AS (
  SELECT device_key||':uplink-core-01' link_key,access_device src,'Ethernet1/49' src_if,core1 dst,'Ethernet1/49' dst_if,device_key||'-uplinks' rg FROM pairs
  UNION ALL
  SELECT device_key||':uplink-core-02',access_device,'Ethernet1/50',core2,'Ethernet1/50',device_key||'-uplinks' FROM pairs
)
INSERT INTO inventory.network_links
  (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,bandwidth_bps,
   utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,last_seen_at)
SELECT link_key,src,src_if,dst,dst_if,'trunk',100000000000,(abs(hashtext(link_key))%5500)/100.0,0.15,0.002,
       'up',rg,true,now()-interval '1 minute' FROM links
ON CONFLICT (link_key) DO UPDATE SET utilization_pct=excluded.utilization_pct,status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Exact switch-port -> server attachment relationship for impact traversal.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,
   relationship_type,status,redundancy_group,is_simulated,attributes,last_seen_at)
SELECT 'attachment:'||a.attachment_key,a.site_id,'access_switch',a.switch_device_id,sw.device_key,
       'server',a.server_id,sv.server_key,'connects_to',CASE a.status WHEN 'up' THEN 'active' ELSE a.status END,sw.device_key||'-server-access',true,
       jsonb_build_object('switch_interface',swi.interface_name,'server_interface',sni.interface_name,
                          'server_ip_addresses',sni.ip_addresses,'vlan_id',v.vlan_id,'vlan_name',v.name,
                          'connection_type',a.connection_type),a.last_seen_at
FROM inventory.server_network_attachments a
JOIN inventory.network_devices sw ON sw.id=a.switch_device_id
JOIN inventory.servers sv ON sv.id=a.server_id
JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id
JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id
LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,attributes=excluded.attributes,last_seen_at=excluded.last_seen_at,updated_at=now();

CREATE OR REPLACE VIEW inventory.server_network_attachment_overview AS
SELECT s.site_key,s.name site_name,sv.server_key,sv.hostname server_name,sv.status server_status,
       r.rack_key,r.name rack_name,sni.interface_name server_interface,sni.mac_address,
       array_to_string(sni.ip_addresses,', ') server_ip_addresses,sw.device_key switch_key,sw.hostname switch_name,
       swi.interface_name switch_interface,sw.manufacturer switch_vendor,sw.model switch_model,
       v.vlan_id,v.name vlan_name,v.vrf_name,v.cidr,v.gateway,a.connection_type,a.status connection_status,
       a.redundancy_role,c1.device_key upstream_core_01,c2.device_key upstream_core_02,
       fw.device_key upstream_firewall,rtr.device_key upstream_router,a.last_seen_at,a.is_simulated
FROM inventory.server_network_attachments a
JOIN inventory.sites s ON s.id=a.site_id
JOIN inventory.servers sv ON sv.id=a.server_id
LEFT JOIN inventory.racks r ON r.id=sv.rack_id
JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id
JOIN inventory.network_devices sw ON sw.id=a.switch_device_id
JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id
LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id
LEFT JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01'
LEFT JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02'
LEFT JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
LEFT JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-wan-rtr-01';

CREATE INDEX IF NOT EXISTS server_network_attachments_server_idx ON inventory.server_network_attachments(server_id);
CREATE INDEX IF NOT EXISTS server_network_attachments_switch_idx ON inventory.server_network_attachments(switch_device_id,switch_interface_id);

COMMIT;
