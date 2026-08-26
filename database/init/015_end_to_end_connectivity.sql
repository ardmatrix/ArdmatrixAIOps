BEGIN;

CREATE TABLE IF NOT EXISTS inventory.topology_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_key text NOT NULL UNIQUE,
  site_id uuid REFERENCES inventory.sites(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  source_key text NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  target_key text NOT NULL,
  relationship_type text NOT NULL CHECK (relationship_type IN
    ('routes_to','protects','connects_to','carries','provides_network','hosts','hosts_node','runs','serves','supports')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','degraded','down','maintenance','unknown')),
  redundancy_group text,
  is_simulated boolean NOT NULL DEFAULT false,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

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
SELECT site_key||'-wan-rtr-01',site_key||'-wan-rtr-01',rack_id,'router','wan-edge','Cisco','ASR 1002-HX',
       'SIM-'||upper(replace(site_key,'-',''))||'-RTR01','IOS XE','17.12.4',
       format('10.%s.0.20',site_no+40)::inet,'active',true,
       jsonb_build_object('monitoring_status','monitored','ha_role','active','firmware_compliance','compliant',
                          'config_backup','current','cpu_utilization_pct',22+site_no*3,
                          'memory_utilization_pct',38+site_no*2,'temperature_c',31+site_no,'open_alerts',0),
       now()-make_interval(mins=>site_no::integer)
FROM site_racks
ON CONFLICT (device_key) DO UPDATE SET attributes=excluded.attributes,status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now();

INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,i.name,'ethernet',CASE WHEN i.name='Management0' THEN ARRAY[nd.management_address] ELSE '{}'::inet[] END,
       1500,i.speed,'up',jsonb_build_object('description',i.description,'operational_status','up',
       'rx_utilization_pct',(abs(hashtext(nd.device_key||i.name))%6500)/100.0,
       'tx_utilization_pct',(abs(hashtext(i.name||nd.device_key))%6200)/100.0,'errors',0)
FROM inventory.network_devices nd
CROSS JOIN (VALUES ('Management0',1000000000::bigint,'Out-of-band management'),
                   ('TenGigabitEthernet0/0/0',10000000000::bigint,'Primary WAN uplink'),
                   ('TenGigabitEthernet0/0/1',10000000000::bigint,'Firewall transit')) i(name,speed,description)
WHERE nd.device_key LIKE '%-wan-rtr-01'
ON CONFLICT DO NOTHING;

WITH devices AS (
  SELECT s.site_key,rtr.id router,fw.id firewall
  FROM inventory.sites s
  JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-wan-rtr-01'
  JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
)
INSERT INTO inventory.network_links
  (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,bandwidth_bps,
   utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,last_seen_at)
SELECT site_key||'-router-firewall',router,'TenGigabitEthernet0/0/1',firewall,'Ethernet1/49','wan',
       10000000000,(abs(hashtext(site_key))%5500)/100.0,0.35,0.005,'up',site_key||'-wan-edge',true,now()-interval '1 minute'
FROM devices
ON CONFLICT (link_key) DO UPDATE SET utilization_pct=excluded.utilization_pct,status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now();

-- Router -> firewall.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,redundancy_group,is_simulated)
SELECT s.site_key||':router:firewall',s.id,'router',rtr.id,rtr.device_key,'firewall',fw.id,fw.device_key,
       'routes_to','active',s.site_key||'-edge',true
FROM inventory.sites s
JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-wan-rtr-01'
JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,last_seen_at=now(),updated_at=now();

-- Firewall -> both core L3 switches.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,redundancy_group,is_simulated)
SELECT s.site_key||':firewall:'||sw.device_key,s.id,'firewall',fw.id,fw.device_key,'l3_switch',sw.id,sw.device_key,
       'protects',CASE WHEN sw.status='active' THEN 'active' ELSE sw.status END,s.site_key||'-core-pair',true
FROM inventory.sites s
JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
JOIN inventory.network_devices sw ON sw.device_key IN (s.site_key||'-core-01',s.site_key||'-core-02')
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,last_seen_at=now(),updated_at=now();

-- L3 switches carry the site VLANs.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,redundancy_group,is_simulated,attributes)
SELECT s.site_key||':'||sw.device_key||':'||v.vlan_key,s.id,'l3_switch',sw.id,sw.device_key,'vlan',v.id,v.vlan_key,
       'carries',CASE WHEN v.status='active' THEN 'active' ELSE v.status END,s.site_key||'-core-pair',true,
       jsonb_build_object('vlan_id',v.vlan_id,'vrf',v.vrf_name,'cidr',v.cidr::text)
FROM inventory.sites s
JOIN inventory.network_devices sw ON sw.device_key IN (s.site_key||'-core-01',s.site_key||'-core-02')
JOIN inventory.network_vlans v ON v.site_id=s.id
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,attributes=excluded.attributes,last_seen_at=now(),updated_at=now();

-- Production/virtualization/Kubernetes VLANs provide connectivity to servers.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated,attributes)
SELECT s.site_key||':'||v.vlan_key||':'||sv.server_key,s.id,'vlan',v.id,v.vlan_key,'server',sv.id,sv.server_key,
       'provides_network',CASE sv.status WHEN 'active' THEN 'active' WHEN 'maintenance' THEN 'maintenance' WHEN 'failed' THEN 'down' ELSE 'unknown' END,true,
       jsonb_build_object('vlan_id',v.vlan_id,'subnet',v.cidr::text,'gateway',v.gateway::text)
FROM inventory.sites s
JOIN inventory.network_vlans v ON v.site_id=s.id AND v.vlan_id=CASE WHEN s.environment='production' THEN 110 ELSE 120 END
JOIN inventory.rooms rm ON rm.site_id=s.id
JOIN inventory.data_center_rows dr ON dr.room_id=rm.id
JOIN inventory.racks r ON r.row_id=dr.id
JOIN inventory.servers sv ON sv.rack_id=r.id
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,attributes=excluded.attributes,last_seen_at=now(),updated_at=now();

-- Physical server -> VM.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated)
SELECT 'server:'||sv.server_key||':vm:'||vm.vm_key,s.id,'server',sv.id,sv.server_key,'vm',vm.id,vm.vm_key,
       'hosts',CASE vm.status WHEN 'running' THEN 'active' WHEN 'failed' THEN 'down' WHEN 'stopped' THEN 'degraded' WHEN 'suspended' THEN 'degraded' ELSE 'unknown' END,true
FROM inventory.virtual_machines vm
JOIN inventory.hypervisors h ON h.id=vm.hypervisor_id
JOIN inventory.servers sv ON sv.id=h.server_id
LEFT JOIN inventory.racks r ON r.id=sv.rack_id
LEFT JOIN inventory.data_center_rows dr ON dr.id=r.row_id
LEFT JOIN inventory.rooms rm ON rm.id=dr.room_id
LEFT JOIN inventory.sites s ON s.id=rm.site_id
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,last_seen_at=now(),updated_at=now();

-- Server/VM -> Kubernetes node.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated)
SELECT 'host:'||coalesce(sv.server_key,vm.vm_key)||':node:'||kn.node_uid,kc.site_id,
       CASE WHEN kn.server_id IS NOT NULL THEN 'server' ELSE 'vm' END,coalesce(sv.id,vm.id),coalesce(sv.server_key,vm.vm_key),
       'k8s_node',kn.id,kn.node_uid,'hosts_node',CASE WHEN kn.status='ready' THEN 'active' ELSE 'degraded' END,true
FROM inventory.k8s_nodes kn
JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id
LEFT JOIN inventory.servers sv ON sv.id=kn.server_id
LEFT JOIN inventory.virtual_machines vm ON vm.id=kn.vm_id
WHERE coalesce(sv.id,vm.id) IS NOT NULL
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,last_seen_at=now(),updated_at=now();

-- Kubernetes node -> pod.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated,attributes)
SELECT 'node:'||kn.node_uid||':pod:'||p.pod_uid,kc.site_id,'k8s_node',kn.id,kn.node_uid,'pod',p.id,p.pod_uid,
       'runs',CASE WHEN p.phase='Running' THEN 'active' ELSE 'degraded' END,true,
       jsonb_build_object('namespace',ns.name,'pod_name',p.name,'pod_ip',p.pod_ip::text)
FROM inventory.k8s_pods p
JOIN inventory.k8s_nodes kn ON kn.id=p.node_id
JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id
JOIN inventory.k8s_namespaces ns ON ns.id=p.namespace_id
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,attributes=excluded.attributes,last_seen_at=now(),updated_at=now();

-- Pod -> application at the same site (deterministic workload placement).
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated,attributes)
SELECT 'pod:'||p.pod_uid||':app:'||a.application_key,kc.site_id,'pod',p.id,p.pod_uid,'application',a.id,a.application_key,
       'serves',CASE WHEN p.phase='Running' AND a.status='active' THEN 'active' ELSE 'degraded' END,true,
       jsonb_build_object('pod_name',p.name,'application_name',a.name)
FROM inventory.k8s_pods p
JOIN inventory.k8s_nodes kn ON kn.id=p.node_id
JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id
JOIN LATERAL (
  SELECT a.id,a.application_key,a.name,a.status FROM inventory.applications a
  WHERE a.attributes->>'site_key'=(SELECT site_key FROM inventory.sites WHERE id=kc.site_id)
  ORDER BY a.application_key OFFSET abs(hashtext(p.pod_uid))%2 LIMIT 1
) a ON true
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,attributes=excluded.attributes,last_seen_at=now(),updated_at=now();

-- Application -> business service.
INSERT INTO inventory.topology_relationships
  (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated)
SELECT 'app:'||a.application_key||':service:'||bs.service_key,aps.site_id,'application',a.id,a.application_key,
       'business_service',bs.id,bs.service_key,'supports','active',true
FROM inventory.business_service_applications bsa
JOIN inventory.applications a ON a.id=bsa.application_id
JOIN inventory.business_services bs ON bs.id=bsa.business_service_id
LEFT JOIN inventory.application_sites aps ON aps.application_id=a.id AND aps.is_primary
ON CONFLICT (relationship_key) DO UPDATE SET status=excluded.status,last_seen_at=now(),updated_at=now();

CREATE OR REPLACE VIEW inventory.topology_relationship_overview AS
SELECT tr.id,tr.relationship_key,s.site_key,s.name site_name,tr.source_type,tr.source_id,tr.source_key,
       tr.relationship_type,tr.target_type,tr.target_id,tr.target_key,tr.status,tr.redundancy_group,
       tr.attributes,tr.last_seen_at,tr.is_simulated
FROM inventory.topology_relationships tr
LEFT JOIN inventory.sites s ON s.id=tr.site_id;

CREATE OR REPLACE VIEW inventory.end_to_end_connectivity_paths AS
SELECT s.site_key,s.name site_name,rtr.device_key router,fw.device_key firewall,sw.device_key l3_switch,
       v.vlan_key,v.vlan_id,v.vrf_name,v.cidr,sv.server_key,sv.hostname server_name,
       vm.vm_key,vm.name vm_name,kc.cluster_key,kn.name k8s_node,p.name pod_name,p.phase pod_phase,
       a.application_key,a.name application_name,bs.service_key,bs.name business_service,
       CASE WHEN p.phase='Running' AND sv.status='active' AND sw.status='active' THEN 'healthy' ELSE 'at_risk' END path_status
FROM inventory.k8s_pods p
JOIN inventory.k8s_nodes kn ON kn.id=p.node_id
JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id
JOIN inventory.sites s ON s.id=kc.site_id
LEFT JOIN inventory.servers sv ON sv.id=kn.server_id
LEFT JOIN inventory.hypervisors h ON h.server_id=sv.id
LEFT JOIN LATERAL (SELECT x.id,x.vm_key,x.name FROM inventory.virtual_machines x WHERE x.hypervisor_id=h.id ORDER BY x.vm_key LIMIT 1) vm ON true
JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-wan-rtr-01'
JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
JOIN inventory.network_devices sw ON sw.device_key=s.site_key||'-core-01'
JOIN inventory.network_vlans v ON v.site_id=s.id AND v.vlan_id=130
LEFT JOIN inventory.topology_relationships pa ON pa.source_type='pod' AND pa.source_id=p.id AND pa.target_type='application'
LEFT JOIN inventory.applications a ON a.id=pa.target_id
LEFT JOIN inventory.business_service_applications bsa ON bsa.application_id=a.id
LEFT JOIN inventory.business_services bs ON bs.id=bsa.business_service_id;

CREATE INDEX IF NOT EXISTS topology_relationships_site_idx ON inventory.topology_relationships(site_id);
CREATE INDEX IF NOT EXISTS topology_relationships_source_idx ON inventory.topology_relationships(source_type,source_id);
CREATE INDEX IF NOT EXISTS topology_relationships_target_idx ON inventory.topology_relationships(target_type,target_id);

COMMIT;
