BEGIN;

-- Simulated cross-data-center backbone. Each site has two diverse links terminating
-- on different core switches so a single core or carrier failure does not isolate it.
WITH ordered_sites AS (
  SELECT s.id,s.site_key,
         row_number() OVER (ORDER BY s.site_key) rn,
         count(*) OVER () site_count
  FROM inventory.sites s
), ring_pairs AS (
  SELECT a.site_key source_site,b.site_key target_site,
         c1.id source_core_1,c2.id source_core_2,
         d1.id target_core_1,d2.id target_core_2
  FROM ordered_sites a
  JOIN ordered_sites b ON b.rn=CASE WHEN a.rn=a.site_count THEN 1 ELSE a.rn+1 END
  JOIN inventory.network_devices c1 ON c1.device_key=a.site_key||'-core-01'
  JOIN inventory.network_devices c2 ON c2.device_key=a.site_key||'-core-02'
  JOIN inventory.network_devices d1 ON d1.device_key=b.site_key||'-core-01'
  JOIN inventory.network_devices d2 ON d2.device_key=b.site_key||'-core-02'
), links AS (
  SELECT source_site||':'||target_site||':backbone-a' link_key,
         source_core_1 source_device,'Ethernet1/53' source_interface,
         target_core_1 target_device,'Ethernet1/53' target_interface,
         'Airtel' provider,'DCI-'||upper(substr(md5(source_site||target_site),1,8))||'-A' circuit_id,
         source_site||':'||target_site||':dci' redundancy_group
  FROM ring_pairs
  UNION ALL
  SELECT source_site||':'||target_site||':backbone-b',
         source_core_2,'Ethernet1/54',target_core_2,'Ethernet1/54',
         'Tata Communications','DCI-'||upper(substr(md5(source_site||target_site),1,8))||'-B',
         source_site||':'||target_site||':dci'
  FROM ring_pairs
)
INSERT INTO inventory.network_links
  (link_key,source_device_id,source_interface,target_device_id,target_interface,
   link_type,provider,circuit_id,bandwidth_bps,utilization_pct,latency_ms,
   packet_loss_pct,status,redundancy_group,is_simulated,last_seen_at,attributes)
SELECT link_key,source_device,source_interface,target_device,target_interface,
       'wan',provider,circuit_id,40000000000,
       24+(abs(hashtext(link_key))%4300)/100.0,
       4+(abs(hashtext(reverse(link_key)))%1800)/100.0,
       (abs(hashtext(link_key||'loss'))%20)/1000.0,
       CASE WHEN link_key LIKE 'dc-delhi:%:backbone-a' THEN 'degraded' ELSE 'up' END,
       redundancy_group,true,now()-interval '1 minute',
       jsonb_build_object('scope','inter_data_center','routing_protocol','eBGP',
                          'encryption','MACsec','discovery_method','simulated_dci')
FROM links
ON CONFLICT (link_key) DO UPDATE SET
  utilization_pct=excluded.utilization_pct,latency_ms=excluded.latency_ms,
  packet_loss_pct=excluded.packet_loss_pct,status=excluded.status,
  provider=excluded.provider,circuit_id=excluded.circuit_id,
  attributes=excluded.attributes,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Interfaces used by the DCI links.
INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,
   administrative_status,attributes)
SELECT nd.id,i.interface_name,'ethernet','{}'::inet[],9216,40000000000,'up',
       jsonb_build_object('description',i.description,'operational_status','up',
                          'layer',3,'mode','routed','scope','inter_data_center')
FROM inventory.network_devices nd
CROSS JOIN (VALUES ('Ethernet1/53','DCI backbone A'),('Ethernet1/54','DCI backbone B')) i(interface_name,description)
WHERE nd.device_key LIKE '%-core-01' OR nd.device_key LIKE '%-core-02'
ON CONFLICT DO NOTHING;

-- Give every physical server a secondary NIC attached to the opposite access switch.
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
  (server_id,interface_name,interface_type,mac_address,ip_addresses,mtu,speed_bps,
   administrative_status,attributes)
SELECT sn.server_id,'ens224','ethernet',
       format('06:%s:%s:%s:%s:%s',substr(md5(sn.server_key),1,2),substr(md5(sn.server_key),3,2),
              substr(md5(sn.server_key),5,2),substr(md5(sn.server_key),7,2),substr(md5(sn.server_key),9,2))::macaddr,
       ARRAY[format('10.%s.10.%s/24',sn.site_no+40,120+sn.rn)::inet],1500,10000000000,'up',
       jsonb_build_object('description','Secondary redundant production adapter','operational_status','up',
                          'layer',3,'bond','bond0','rx_utilization_pct',(abs(hashtext(sn.server_key||'secondary'))%4200)/100.0,
                          'tx_utilization_pct',(abs(hashtext(sn.server_key||'backup'))%3900)/100.0,'errors',0)
FROM server_numbering sn
ON CONFLICT DO NOTHING;

WITH server_numbering AS (
  SELECT s.id site_id,s.site_key,sv.id server_id,sv.server_key,
         row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) rn
  FROM inventory.sites s
  JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
  JOIN inventory.racks r ON r.row_id=dr.id
  JOIN inventory.servers sv ON sv.rack_id=r.id
), secondary_ports AS (
  SELECT sn.*,sw.id switch_id,
         'Ethernet1/2/'||ceil(sn.rn/2.0)::integer switch_interface
  FROM server_numbering sn
  JOIN inventory.network_devices sw
    ON sw.device_key=sn.site_key||'-access-'||lpad((2-(sn.rn-1)%2)::text,2,'0')
)
INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,
   administrative_status,attributes)
SELECT sp.switch_id,sp.switch_interface,'ethernet','{}'::inet[],1500,10000000000,'up',
       jsonb_build_object('description','Redundant server port · '||sp.server_key,
                          'operational_status','up','layer',2,'mode','access','access_vlan',110)
FROM secondary_ports sp
ON CONFLICT DO NOTHING;

WITH server_numbering AS (
  SELECT s.id site_id,s.site_key,sv.id server_id,sv.server_key,sv.status,
         row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) rn
  FROM inventory.sites s
  JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
  JOIN inventory.racks r ON r.row_id=dr.id
  JOIN inventory.servers sv ON sv.rack_id=r.id
)
INSERT INTO inventory.server_network_attachments
  (attachment_key,site_id,server_id,server_interface_id,switch_device_id,switch_interface_id,
   vlan_id,connection_type,status,redundancy_role,is_simulated,attributes,last_seen_at)
SELECT sn.server_key||':ens224:'||sw.device_key||':'||swi.interface_name,
       sn.site_id,sn.server_id,sni.id,sw.id,swi.id,v.id,'bond',
       CASE WHEN sn.status='failed' THEN 'down' WHEN sn.status='maintenance' THEN 'maintenance' ELSE 'up' END,
       'secondary',true,
       jsonb_build_object('native_vlan',110,'port_mode','access','bond','bond0',
                          'discovery_method','simulated-lldp'),now()-interval '1 minute'
FROM server_numbering sn
JOIN inventory.network_interfaces sni ON sni.server_id=sn.server_id AND sni.interface_name='ens224'
JOIN inventory.network_devices sw
  ON sw.device_key=sn.site_key||'-access-'||lpad((2-(sn.rn-1)%2)::text,2,'0')
JOIN inventory.network_interfaces swi
  ON swi.network_device_id=sw.id AND swi.interface_name='Ethernet1/2/'||ceil(sn.rn/2.0)::integer
JOIN inventory.network_vlans v ON v.site_id=sn.site_id AND v.vlan_id=110
ON CONFLICT (attachment_key) DO UPDATE SET
  status=excluded.status,attributes=excluded.attributes,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Refresh switch-to-server topology edges for both primary and secondary paths.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,
   relationship_type,status,redundancy_group,is_simulated,attributes,last_seen_at)
SELECT 'attachment:'||a.attachment_key,a.site_id,'access_switch',a.switch_device_id,sw.device_key,
       'server',a.server_id,sv.server_key,'connects_to',
       CASE a.status WHEN 'up' THEN 'active' ELSE a.status END,
       sv.server_key||'-dual-homed',true,
       jsonb_build_object('switch_interface',swi.interface_name,'server_interface',sni.interface_name,
                          'server_ip_addresses',sni.ip_addresses,'vlan_id',v.vlan_id,
                          'vlan_name',v.name,'connection_type',a.connection_type,
                          'redundancy_role',a.redundancy_role),a.last_seen_at
FROM inventory.server_network_attachments a
JOIN inventory.network_devices sw ON sw.id=a.switch_device_id
JOIN inventory.servers sv ON sv.id=a.server_id
JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id
JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id
LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id
ON CONFLICT (relationship_key) DO UPDATE SET
  status=excluded.status,redundancy_group=excluded.redundancy_group,
  attributes=excluded.attributes,last_seen_at=excluded.last_seen_at,updated_at=now();

CREATE OR REPLACE VIEW inventory.data_center_backbone_overview AS
SELECT nl.link_key,ss.site_key source_site_key,ss.name source_site,
       sd.device_key source_core,nl.source_interface,
       ts.site_key target_site_key,ts.name target_site,
       td.device_key target_core,nl.target_interface,
       nl.provider,nl.circuit_id,nl.bandwidth_bps,nl.utilization_pct,
       nl.latency_ms,nl.packet_loss_pct,nl.status,nl.redundancy_group,
       nl.is_simulated,nl.last_seen_at
FROM inventory.network_links nl
JOIN inventory.network_devices sd ON sd.id=nl.source_device_id
JOIN inventory.racks sr ON sr.id=sd.rack_id
JOIN inventory.data_center_rows sdr ON sdr.id=sr.row_id
JOIN inventory.rooms srm ON srm.id=sdr.room_id
JOIN inventory.sites ss ON ss.id=srm.site_id
JOIN inventory.network_devices td ON td.id=nl.target_device_id
JOIN inventory.racks tr ON tr.id=td.rack_id
JOIN inventory.data_center_rows tdr ON tdr.id=tr.row_id
JOIN inventory.rooms trm ON trm.id=tdr.room_id
JOIN inventory.sites ts ON ts.id=trm.site_id
WHERE nl.attributes->>'scope'='inter_data_center';

CREATE OR REPLACE VIEW inventory.site_physical_connectivity_overview AS
SELECT s.site_key,s.name site_name,c1.device_key core_switch_a,c2.device_key core_switch_b,
       sw.device_key access_switch,swi.interface_name switch_interface,
       sv.server_key,sv.hostname server_name,sni.interface_name server_interface,
       a.redundancy_role,a.connection_type,a.status connection_status,
       v.vlan_id,v.name vlan_name,a.is_simulated,a.last_seen_at
FROM inventory.server_network_attachments a
JOIN inventory.sites s ON s.id=a.site_id
JOIN inventory.servers sv ON sv.id=a.server_id
JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id
JOIN inventory.network_devices sw ON sw.id=a.switch_device_id
JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id
LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id
LEFT JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01'
LEFT JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02';

CREATE INDEX IF NOT EXISTS network_links_redundancy_idx
  ON inventory.network_links(redundancy_group,status);
CREATE INDEX IF NOT EXISTS server_network_attachments_redundancy_idx
  ON inventory.server_network_attachments(server_id,redundancy_role,status);

COMMIT;
