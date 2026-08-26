BEGIN;

-- Replace the earlier simulated estate with the approved four-data-center reference model.
TRUNCATE inventory.sites CASCADE;
TRUNCATE inventory.applications CASCADE;
TRUNCATE inventory.business_services CASCADE;

INSERT INTO inventory.sites
  (id,site_key,name,site_type,status,address,latitude,longitude,timezone,is_simulated,
   region,environment,health_status,facility_power_capacity_kw,facility_power_used_kw,
   cooling_capacity_kw,temperature_c,humidity_pct,pue,monitoring_coverage_pct,inventory_completeness_pct,attributes)
VALUES
  (md5('site-dc-chicago')::uuid,'dc-chicago','Chicago Data Center','data_center','active','{"city":"Chicago","country":"United States"}',41.878100,-87.629800,'America/Chicago',true,'North America','production','healthy',4200,2780,4500,22.4,44,1.31,99,100,'{"tier":"Tier III+","design":"simulated reference"}'),
  (md5('site-dc-london')::uuid,'dc-london','London Data Center','data_center','active','{"city":"London","country":"United Kingdom"}',51.507200,-0.127600,'Europe/London',true,'Europe','production','healthy',3900,2540,4200,21.8,46,1.29,99,100,'{"tier":"Tier III+","design":"simulated reference"}'),
  (md5('site-dc-singapore')::uuid,'dc-singapore','Singapore Data Center','data_center','active','{"city":"Singapore","country":"Singapore"}',1.352100,103.819800,'Asia/Singapore',true,'Asia Pacific','production','warning',4600,3290,5000,23.6,53,1.38,98,100,'{"tier":"Tier IV","design":"simulated reference"}'),
  (md5('site-dc-mumbai')::uuid,'dc-mumbai','Mumbai Data Center','data_center','active','{"city":"Mumbai","country":"India"}',19.076000,72.877700,'Asia/Kolkata',true,'India','production','healthy',4400,3010,4800,23.1,55,1.35,99,100,'{"tier":"Tier III+","design":"simulated reference"}');

INSERT INTO inventory.rooms (id,site_id,room_key,name,floor,status,is_simulated,attributes)
SELECT md5(s.site_key||'-room-main')::uuid,s.id,'room-main','Main Data Hall','1','active',true,'{"containment":"hot aisle"}'
FROM inventory.sites s;
INSERT INTO inventory.data_center_rows (id,room_id,row_key,name,is_simulated)
SELECT md5(s.site_key||'-row-a')::uuid,rm.id,'row-a','Compute Row A',true
FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id;
INSERT INTO inventory.racks (id,row_id,rack_key,name,rack_units,max_power_watts,status,is_simulated,attributes)
SELECT md5(s.site_key||'-rack-'||r)::uuid,dr.id,s.site_key||'-rack-'||lpad(r::text,2,'0'),'Rack '||lpad(r::text,2,'0'),48,18000,'active',true,
       jsonb_build_object('rack_number',r,'power_feed','A+B','design','10 servers + 2 access switches')
FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id
JOIN inventory.data_center_rows dr ON dr.room_id=rm.id CROSS JOIN generate_series(1,3) r;

-- Ten mixed-OS physical servers per rack.
WITH rack_sites AS (
  SELECT s.site_key,r.id rack_id,r.rack_key,dense_rank() OVER (ORDER BY s.site_key) site_no,
         row_number() OVER (PARTITION BY s.id ORDER BY r.rack_key) rack_no
  FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id
  JOIN inventory.data_center_rows dr ON dr.room_id=rm.id JOIN inventory.racks r ON r.row_id=dr.id
)
INSERT INTO inventory.servers
  (id,server_key,hostname,rack_id,rack_unit_start,rack_unit_height,server_type,manufacturer,model,
   serial_number,asset_tag,architecture,operating_system,operating_system_version,bios_version,bmc_address,
   status,is_simulated,attributes,last_seen_at)
SELECT md5(rs.rack_key||'-server-'||n)::uuid,rs.rack_key||'-srv-'||lpad(n::text,2,'0'),
       rs.rack_key||'-srv-'||lpad(n::text,2,'0'),rs.rack_id,2+(n-1)*4,2,'physical',
       (ARRAY['Dell','HPE','Lenovo'])[((n-1)%3)+1],
       (ARRAY['PowerEdge R760','ProLiant DL380 Gen11','ThinkSystem SR650 V3'])[((n-1)%3)+1],
       'SIM-'||upper(substr(md5(rs.rack_key||n),1,14)),'AST-'||upper(substr(md5('asset'||rs.rack_key||n),1,10)),'x86_64',
       (ARRAY['VMware ESXi','Red Hat Enterprise Linux','Ubuntu Server','Windows Server','Rocky Linux'])[((n-1)%5)+1],
       (ARRAY['8.0 U3','9.5','24.04 LTS','2025','9.5'])[((n-1)%5)+1],'2.9.1',
       format('10.%s.%s.%s',60+rs.site_no,rs.rack_no,20+n)::inet,
       CASE WHEN rs.site_key='dc-singapore' AND rs.rack_no=3 AND n=10 THEN 'maintenance' ELSE 'active' END,true,
       jsonb_build_object('cpu_sockets',2,'physical_cores',32,'ram_gb',256,'storage_tb',8,'monitoring_status','monitored'),
       now()-make_interval(mins=>(n%3)+1)
FROM rack_sites rs CROSS JOIN generate_series(1,10) n;

INSERT INTO inventory.hypervisors (id,hypervisor_key,server_id,hypervisor_type,version,cluster_name,status,is_simulated)
SELECT md5('hv-'||server_key)::uuid,'hv-'||server_key,id,
       CASE WHEN operating_system='VMware ESXi' THEN 'VMware ESXi' ELSE 'KVM' END,
       CASE WHEN operating_system='VMware ESXi' THEN '8.0 U3' ELSE 'libvirt 10.0' END,
       split_part(server_key,'-rack-',1)||'-compute','active',true FROM inventory.servers;

-- Three VMs per physical server with workload-specific operating systems.
WITH hv_numbered AS (
 SELECT h.*,sv.server_key,s.site_key,dense_rank() OVER (ORDER BY s.site_key) site_no,
        row_number() OVER (PARTITION BY s.id ORDER BY sv.server_key) server_no
 FROM inventory.hypervisors h JOIN inventory.servers sv ON sv.id=h.server_id
 JOIN inventory.racks r ON r.id=sv.rack_id JOIN inventory.data_center_rows dr ON dr.id=r.row_id
 JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
)
INSERT INTO inventory.virtual_machines
 (id,vm_key,name,hostname,hypervisor_id,vcpu_count,memory_bytes,provisioned_storage_bytes,
  operating_system,operating_system_version,ip_addresses,status,is_simulated,attributes,last_seen_at)
SELECT md5(h.server_key||'-vm-'||v)::uuid,h.server_key||'-vm-'||v,upper(replace(h.site_key,'dc-',''))||' VM '||lpad(h.server_no::text,2,'0')||'-'||v,
       h.server_key||'-vm-'||v,h.id,CASE v WHEN 1 THEN 8 WHEN 2 THEN 4 ELSE 4 END,
       CASE v WHEN 1 THEN 34359738368 WHEN 2 THEN 17179869184 ELSE 8589934592 END,
       CASE v WHEN 1 THEN 536870912000 WHEN 2 THEN 268435456000 ELSE 161061273600 END,
       (ARRAY['Red Hat Enterprise Linux','Ubuntu Server','Windows Server'])[(v-1)%3+1],
       (ARRAY['9.5','24.04 LTS','2025'])[(v-1)%3+1],
       ARRAY[format('10.%s.20.%s',60+h.site_no,(h.server_no-1)*3+v+10)::inet],
       CASE WHEN h.site_key='dc-singapore' AND h.server_no=30 AND v=3 THEN 'stopped' ELSE 'running' END,true,
       jsonb_build_object('workload_role',CASE v WHEN 1 THEN 'application' WHEN 2 THEN 'database' ELSE 'utility' END),now()-interval '1 minute'
FROM hv_numbered h CROSS JOIN generate_series(1,3) v;

-- Four routed VLANs per data center.
WITH ns AS (SELECT s.*,dense_rank() OVER (ORDER BY site_key) site_no FROM inventory.sites s)
INSERT INTO inventory.network_vlans
 (id,vlan_key,site_id,vlan_id,name,purpose,vrf_name,cidr,gateway,allocated_addresses,capacity_addresses,status,is_simulated,attributes)
SELECT md5(s.site_key||'-vlan-'||v.id)::uuid,s.site_key||'-vlan-'||v.id,s.id,v.id,v.name,v.purpose,v.vrf,
       format('10.%s.%s.0/24',60+s.site_no,v.octet)::cidr,format('10.%s.%s.1',60+s.site_no,v.octet)::inet,
       v.used,254,'active',true,jsonb_build_object('gateway_redundancy','HSRP','security_zone',v.zone)
FROM ns s CROSS JOIN (VALUES
 (110,'Billing','billing','BILLING',10,44,'restricted'),
 (120,'Applications','application','PROD',20,98,'production'),
 (130,'Management','management','MGMT',30,52,'management'),
 (140,'Shared Services','dns-ntp-backup','SERVICES',40,38,'shared')) v(id,name,purpose,vrf,octet,used,zone);

-- Per DC: router pair, firewall pair, L3 core pair; per rack: two 48-port L2 access switches.
WITH first_rack AS (SELECT s.site_key,r.id rack_id,dense_rank() OVER (ORDER BY s.site_key) site_no
 FROM inventory.sites s JOIN LATERAL (SELECT r.id FROM inventory.racks r JOIN inventory.data_center_rows dr ON dr.id=r.row_id JOIN inventory.rooms rm ON rm.id=dr.room_id WHERE rm.site_id=s.id ORDER BY r.rack_key LIMIT 1) r ON true),
devices AS (SELECT f.*,x.role,x.dtype,x.num,x.vendor,x.model FROM first_rack f CROSS JOIN (VALUES
 ('core-rtr-01','router',1,'Cisco','ASR 1002-HX'),('core-rtr-02','router',2,'Cisco','ASR 1002-HX'),
 ('edge-fw-01','firewall',3,'Palo Alto Networks','PA-5450'),('edge-fw-02','firewall',4,'Palo Alto Networks','PA-5450'),
 ('core-01','switch',5,'Cisco','Nexus 9364C'),('core-02','switch',6,'Cisco','Nexus 9364C')) x(role,dtype,num,vendor,model))
INSERT INTO inventory.network_devices
 (id,device_key,hostname,rack_id,device_type,role,manufacturer,model,serial_number,operating_system,
  operating_system_version,management_address,status,is_simulated,attributes,last_seen_at)
SELECT md5(site_key||'-'||role)::uuid,site_key||'-'||role,site_key||'-'||role,rack_id,dtype,role,vendor,model,
 'SIM-'||upper(substr(md5(site_key||role),1,14)),CASE dtype WHEN 'switch' THEN 'NX-OS' WHEN 'router' THEN 'IOS-XE' ELSE 'PAN-OS' END,
 CASE dtype WHEN 'switch' THEN '10.4(2)' WHEN 'router' THEN '17.12.4' ELSE '11.1.4' END,
 format('10.%s.0.%s',60+site_no,10+num)::inet,'active',true,
 jsonb_build_object('ha_role',CASE WHEN role LIKE '%01' THEN 'active' ELSE 'standby' END,'monitoring_status','monitored','open_alerts',0),now()-interval '1 minute'
FROM devices;

WITH rack_sites AS (SELECT s.site_key,r.id rack_id,r.rack_key,dense_rank() OVER (ORDER BY s.site_key) site_no,
 row_number() OVER (PARTITION BY s.id ORDER BY r.rack_key) rack_no FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id JOIN inventory.data_center_rows dr ON dr.room_id=rm.id JOIN inventory.racks r ON r.row_id=dr.id)
INSERT INTO inventory.network_devices
 (id,device_key,hostname,rack_id,device_type,role,manufacturer,model,serial_number,operating_system,operating_system_version,management_address,status,is_simulated,attributes,last_seen_at)
SELECT md5(rs.rack_key||'-access-'||a)::uuid,rs.rack_key||'-access-'||lpad(a::text,2,'0'),rs.rack_key||'-access-'||lpad(a::text,2,'0'),rs.rack_id,
 'switch','access-l2','Cisco','Catalyst C9300-48T','SIM-'||upper(substr(md5(rs.rack_key||a),1,14)),'IOS-XE','17.12.4',
 format('10.%s.%s.%s',60+rs.site_no,rs.rack_no,10+a)::inet,'active',true,
 jsonb_build_object('switching_layer','L2','port_count',48,'port_mix','24 Ethernet + 24 GigabitEthernet','monitoring_status','monitored'),now()-interval '1 minute'
FROM rack_sites rs CROSS JOIN generate_series(1,2) a;

-- Management, fabric and 48 front-panel interfaces for every network device.
INSERT INTO inventory.network_interfaces (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,'Management0','ethernet',ARRAY[nd.management_address],1500,1000000000,'up','{"operational_status":"up","layer":3,"description":"Out-of-band management"}' FROM inventory.network_devices nd;
INSERT INTO inventory.network_interfaces (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,CASE WHEN p<=24 THEN 'Ethernet1/'||p ELSE 'GigabitEthernet1/0/'||(p-24) END,
 CASE WHEN p<=24 THEN 'ethernet' ELSE 'gigabit_ethernet' END,'{}',1500,1000000000,'up',
 jsonb_build_object('operational_status','up','layer',2,'description','48-port rack access interface','port_number',p)
FROM inventory.network_devices nd CROSS JOIN generate_series(1,48) p WHERE nd.role='access-l2';
INSERT INTO inventory.network_interfaces (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT nd.id,i.name,'ethernet','{}',9216,i.speed,'up',jsonb_build_object('operational_status','up','layer',3,'description',i.description)
FROM inventory.network_devices nd CROSS JOIN (VALUES ('Ethernet1/49',100000000000::bigint,'Fabric uplink A'),('Ethernet1/50',100000000000::bigint,'Fabric uplink B'),('Port-Channel10',200000000000::bigint,'HA peer link'),('Ethernet1/53',40000000000::bigint,'DCI A'),('Ethernet1/54',40000000000::bigint,'DCI B')) i(name,speed,description)
WHERE nd.role IN ('access-l2','core-01','core-02','edge-fw-01','edge-fw-02','core-rtr-01','core-rtr-02');

-- Dual server NICs and exact rack-switch port attachments.
WITH sn AS (SELECT s.id site_id,s.site_key,r.rack_key,sv.id server_id,sv.server_key,
 row_number() OVER (PARTITION BY r.id ORDER BY sv.server_key) server_no,dense_rank() OVER (ORDER BY s.site_key) site_no
 FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id JOIN inventory.data_center_rows dr ON dr.room_id=rm.id JOIN inventory.racks r ON r.row_id=dr.id JOIN inventory.servers sv ON sv.rack_id=r.id)
INSERT INTO inventory.network_interfaces (server_id,interface_name,interface_type,mac_address,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT sn.server_id,n.nic,'ethernet',format('%s:%s:%s:%s:%s:%s',n.prefix,substr(md5(sn.server_key||n.nic),1,2),substr(md5(sn.server_key||n.nic),3,2),substr(md5(sn.server_key||n.nic),5,2),substr(md5(sn.server_key||n.nic),7,2),substr(md5(sn.server_key||n.nic),9,2))::macaddr,
 ARRAY[format('10.%s.20.%s',60+sn.site_no,(row_number() OVER (PARTITION BY sn.site_id ORDER BY sn.server_key,n.nic))+20)::inet],1500,10000000000,'up',
 jsonb_build_object('operational_status','up','bond','bond0','description',n.role||' production NIC')
FROM sn CROSS JOIN (VALUES ('ens192','02','Primary'),('ens224','06','Secondary')) n(nic,prefix,role);

WITH sn AS (SELECT s.id site_id,s.site_key,r.rack_key,sv.id server_id,sv.server_key,row_number() OVER (PARTITION BY r.id ORDER BY sv.server_key) server_no
 FROM inventory.sites s JOIN inventory.rooms rm ON rm.site_id=s.id JOIN inventory.data_center_rows dr ON dr.room_id=rm.id JOIN inventory.racks r ON r.row_id=dr.id JOIN inventory.servers sv ON sv.rack_id=r.id)
INSERT INTO inventory.server_network_attachments
 (attachment_key,site_id,server_id,server_interface_id,switch_device_id,switch_interface_id,vlan_id,connection_type,status,redundancy_role,is_simulated,attributes,last_seen_at)
SELECT sn.server_key||':'||n.nic||':'||sw.device_key,sn.site_id,sn.server_id,sni.id,sw.id,swi.id,v.id,'bond','up',n.rr,true,
 jsonb_build_object('port_mode','access','bond','bond0','native_vlan',120,'discovery_method','simulated-lldp'),now()-interval '1 minute'
FROM sn CROSS JOIN (VALUES ('ens192',1,'primary'),('ens224',2,'secondary')) n(nic,sw_no,rr)
JOIN inventory.network_interfaces sni ON sni.server_id=sn.server_id AND sni.interface_name=n.nic
JOIN inventory.network_devices sw ON sw.device_key=sn.rack_key||'-access-'||lpad(n.sw_no::text,2,'0')
JOIN inventory.network_interfaces swi ON swi.network_device_id=sw.id AND swi.interface_name=CASE WHEN n.sw_no=1 THEN 'Ethernet1/'||sn.server_no ELSE 'GigabitEthernet1/0/'||sn.server_no END
JOIN inventory.network_vlans v ON v.site_id=sn.site_id AND v.vlan_id=120;

-- Intra-site redundant fabric links.
WITH d AS (SELECT s.site_key,c1.id c1,c2.id c2,f1.id f1,f2.id f2,r1.id r1,r2.id r2 FROM inventory.sites s
 JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01' JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02'
 JOIN inventory.network_devices f1 ON f1.device_key=s.site_key||'-edge-fw-01' JOIN inventory.network_devices f2 ON f2.device_key=s.site_key||'-edge-fw-02'
 JOIN inventory.network_devices r1 ON r1.device_key=s.site_key||'-core-rtr-01' JOIN inventory.network_devices r2 ON r2.device_key=s.site_key||'-core-rtr-02'),
l AS (SELECT site_key||'-core-peer' k,c1 s,'Port-Channel10' si,c2 t,'Port-Channel10' ti,'port_channel' ty,site_key||'-core-ha' rg FROM d UNION ALL
 SELECT site_key||'-fw1-core1',f1,'Ethernet1/49',c1,'Ethernet1/49','trunk',site_key||'-fabric-a' FROM d UNION ALL SELECT site_key||'-fw2-core2',f2,'Ethernet1/50',c2,'Ethernet1/50','trunk',site_key||'-fabric-b' FROM d UNION ALL
 SELECT site_key||'-rtr1-fw1',r1,'Ethernet1/49',f1,'Ethernet1/49','trunk',site_key||'-edge-a' FROM d UNION ALL SELECT site_key||'-rtr2-fw2',r2,'Ethernet1/50',f2,'Ethernet1/50','trunk',site_key||'-edge-b' FROM d)
INSERT INTO inventory.network_links (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,bandwidth_bps,utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,attributes)
SELECT k,s,si,t,ti,ty,100000000000,20+(abs(hashtext(k))%4500)/100.0,.2,.001,'up',rg,true,'{"scope":"intra_site"}' FROM l;

WITH a AS (SELECT s.site_key,nd.id access_id,nd.device_key FROM inventory.sites s JOIN inventory.network_devices nd ON nd.device_key LIKE s.site_key||'-rack-%-access-%'),
p AS (SELECT a.*,c1.id c1,c2.id c2 FROM a JOIN inventory.network_devices c1 ON c1.device_key=a.site_key||'-core-01' JOIN inventory.network_devices c2 ON c2.device_key=a.site_key||'-core-02'),
l AS (SELECT device_key||'-uplink-a' k,access_id s,'Ethernet1/49' si,c1 t,'Ethernet1/49' ti,device_key||'-uplinks' rg FROM p UNION ALL SELECT device_key||'-uplink-b',access_id,'Ethernet1/50',c2,'Ethernet1/50',device_key||'-uplinks' FROM p)
INSERT INTO inventory.network_links (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,bandwidth_bps,utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,attributes)
SELECT k,s,si,t,ti,'trunk',100000000000,18+(abs(hashtext(k))%4700)/100.0,.15,.001,'up',rg,true,'{"scope":"rack_fabric"}' FROM l;

-- Two diverse DCI rings cross-connect all four data centers through both core routers.
WITH os AS (SELECT s.site_key,row_number() OVER (ORDER BY CASE site_key WHEN 'dc-chicago' THEN 1 WHEN 'dc-london' THEN 2 WHEN 'dc-singapore' THEN 3 ELSE 4 END) rn FROM inventory.sites s),
p AS (SELECT a.site_key src,b.site_key dst,r1.id sr1,r2.id sr2,t1.id tr1,t2.id tr2 FROM os a JOIN os b ON b.rn=CASE WHEN a.rn=4 THEN 1 ELSE a.rn+1 END JOIN inventory.network_devices r1 ON r1.device_key=a.site_key||'-core-rtr-01' JOIN inventory.network_devices r2 ON r2.device_key=a.site_key||'-core-rtr-02' JOIN inventory.network_devices t1 ON t1.device_key=b.site_key||'-core-rtr-01' JOIN inventory.network_devices t2 ON t2.device_key=b.site_key||'-core-rtr-02'),
l AS (SELECT src||':'||dst||':dci-a' k,sr1 s,tr1 t,'Airtel' provider,src||':'||dst||':dci' rg FROM p UNION ALL SELECT src||':'||dst||':dci-b',sr2,tr2,'Tata Communications',src||':'||dst||':dci' FROM p)
INSERT INTO inventory.network_links (link_key,source_device_id,source_interface,target_device_id,target_interface,link_type,provider,circuit_id,bandwidth_bps,utilization_pct,latency_ms,packet_loss_pct,status,redundancy_group,is_simulated,attributes)
SELECT k,s,'Ethernet1/53',t,'Ethernet1/54','wan',provider,'SIM-'||upper(substr(md5(k),1,10)),40000000000,22+(abs(hashtext(k))%4200)/100.0,5+(abs(hashtext(k))%1500)/100.0,.005,'up',rg,true,'{"scope":"inter_data_center","routing_protocol":"eBGP","encryption":"MACsec"}' FROM l;

-- Two clusters and six VM-backed nodes per site; three pods per node.
INSERT INTO inventory.k8s_clusters (id,cluster_key,name,site_id,distribution,version,api_endpoint,status,is_simulated,attributes)
SELECT md5(s.site_key||'-k8s-'||c)::uuid,s.site_key||'-k8s-'||c,upper(replace(s.site_key,'dc-',''))||' Kubernetes '||c,s.id,
 CASE c WHEN 1 THEN 'OpenShift' ELSE 'Rancher Kubernetes' END,'v1.33','https://'||s.site_key||'-k8s-'||c||'.example.invalid:6443','active',true,jsonb_build_object('cluster_number',c)
FROM inventory.sites s CROSS JOIN generate_series(1,2) c;
INSERT INTO inventory.k8s_namespaces (id,cluster_id,namespace_uid,name,status,labels,is_simulated)
SELECT md5(c.cluster_key||'-production')::uuid,c.id,c.cluster_key||'-production','production','active','{"environment":"production"}',true FROM inventory.k8s_clusters c;
WITH cvm AS (SELECT c.id cluster_id,c.cluster_key,c.site_id,v.id vm_id,row_number() OVER (PARTITION BY c.id ORDER BY v.vm_key) rn
 FROM inventory.k8s_clusters c JOIN inventory.sites s ON s.id=c.site_id JOIN inventory.virtual_machines v ON v.vm_key LIKE s.site_key||'%'
 WHERE ((abs(hashtext(v.vm_key))%2)+1)=(c.attributes->>'cluster_number')::int
)
INSERT INTO inventory.k8s_nodes (id,cluster_id,node_uid,name,vm_id,role,architecture,operating_system,kernel_version,kubelet_version,cpu_capacity_millicores,memory_capacity_bytes,status,labels,is_simulated)
SELECT md5(cluster_key||'-node-'||rn)::uuid,cluster_id,cluster_key||'-node-'||rn,cluster_key||'-node-'||rn,vm_id,
 CASE WHEN rn=1 THEN 'control_plane_worker' ELSE 'worker' END,'amd64','linux','6.8','v1.33',4000,17179869184,'ready',jsonb_build_object('zone',rn,'topology','vm-backed'),true
FROM cvm WHERE rn<=3;
INSERT INTO inventory.k8s_pods (id,namespace_id,node_id,pod_uid,name,phase,pod_ip,qos_class,restart_policy,labels,is_simulated)
SELECT md5(n.node_uid||'-pod-'||p)::uuid,ns.id,n.id,n.node_uid||'-pod-'||p,
 split_part(n.name,'-k8s-',1)||'-'||(ARRAY['billing','application','shared-services'])[p]||'-pod-'||right(n.name,1),
 CASE WHEN n.cluster_id=(SELECT id FROM inventory.k8s_clusters WHERE cluster_key='dc-singapore-k8s-2') AND p=3 AND right(n.name,1)='3' THEN 'Pending' ELSE 'Running' END,
 NULL,'Burstable','Always',jsonb_build_object('application_index',p),true
FROM inventory.k8s_nodes n JOIN inventory.k8s_namespaces ns ON ns.cluster_id=n.cluster_id CROSS JOIN generate_series(1,3) p;

INSERT INTO inventory.business_services (id,service_key,name,description,criticality,service_tier,status,is_simulated)
VALUES (md5('billing-service')::uuid,'billing-service','Global Billing','Billing and invoicing','critical','tier-1','active',true),
 (md5('customer-app-service')::uuid,'customer-app-service','Customer Applications','Customer-facing application service','critical','tier-1','active',true),
 (md5('shared-platform-service')::uuid,'shared-platform-service','Shared Platform Services','Common platform capabilities','high','tier-2','active',true);
INSERT INTO inventory.applications (id,application_key,name,description,application_type,version,environment,criticality,status,is_simulated,attributes)
SELECT md5(s.site_key||'-app-'||a)::uuid,s.site_key||'-app-'||a,upper(replace(s.site_key,'dc-',''))||' '||(ARRAY['Billing Platform','Customer Application','Shared Services'])[a],
 'Simulated application deployed on the site Kubernetes platform','microservices','3.0','production',CASE a WHEN 1 THEN 'critical' WHEN 2 THEN 'high' ELSE 'medium' END,'active',true,jsonb_build_object('site_key',s.site_key,'application_index',a)
FROM inventory.sites s CROSS JOIN generate_series(1,3) a;
INSERT INTO inventory.application_sites (application_id,site_id,is_primary,role,is_simulated)
SELECT a.id,s.id,true,'primary',true FROM inventory.applications a JOIN inventory.sites s ON s.site_key=a.attributes->>'site_key';
INSERT INTO inventory.business_service_applications (business_service_id,application_id,relationship_type,is_simulated)
SELECT bs.id,a.id,'supports',true FROM inventory.applications a JOIN inventory.business_services bs ON bs.service_key=(ARRAY['billing-service','customer-app-service','shared-platform-service'])[(a.attributes->>'application_index')::int];

-- Explicit pod-to-application and access-switch-to-server topology edges.
INSERT INTO inventory.topology_relationships (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,is_simulated,attributes)
SELECT 'pod-app-'||p.pod_uid,s.id,'pod',p.id,p.pod_uid,'application',a.id,a.application_key,'serves','active',true,jsonb_build_object('mapping','application_index')
FROM inventory.k8s_pods p JOIN inventory.k8s_namespaces ns ON ns.id=p.namespace_id JOIN inventory.k8s_clusters c ON c.id=ns.cluster_id JOIN inventory.sites s ON s.id=c.site_id
JOIN inventory.applications a ON a.attributes->>'site_key'=s.site_key AND (a.attributes->>'application_index')::int=(p.labels->>'application_index')::int;
INSERT INTO inventory.topology_relationships (relationship_key,site_id,source_type,source_id,source_key,target_type,target_id,target_key,relationship_type,status,redundancy_group,is_simulated,attributes)
SELECT 'attachment:'||a.attachment_key,a.site_id,'access_switch',a.switch_device_id,sw.device_key,'server',a.server_id,sv.server_key,'connects_to','active',sv.server_key||'-dual-homed',true,
 jsonb_build_object('switch_interface',swi.interface_name,'server_interface',sni.interface_name,'redundancy_role',a.redundancy_role,'vlan_id',v.vlan_id)
FROM inventory.server_network_attachments a JOIN inventory.network_devices sw ON sw.id=a.switch_device_id JOIN inventory.servers sv ON sv.id=a.server_id JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id;

-- Refresh operational views for the approved hierarchy and VM-backed Kubernetes nodes.
CREATE OR REPLACE VIEW inventory.server_network_attachment_overview AS
SELECT s.site_key,s.name site_name,sv.server_key,sv.hostname server_name,sv.status server_status,r.rack_key,r.name rack_name,
 sni.interface_name server_interface,sni.mac_address,array_to_string(sni.ip_addresses,', ') server_ip_addresses,
 sw.device_key switch_key,sw.hostname switch_name,swi.interface_name switch_interface,sw.manufacturer switch_vendor,sw.model switch_model,
 v.vlan_id,v.name vlan_name,v.vrf_name,v.cidr,v.gateway,a.connection_type,a.status connection_status,a.redundancy_role,
 c1.device_key upstream_core_01,c2.device_key upstream_core_02,fw.device_key upstream_firewall,rtr.device_key upstream_router,a.last_seen_at,a.is_simulated
FROM inventory.server_network_attachments a JOIN inventory.sites s ON s.id=a.site_id JOIN inventory.servers sv ON sv.id=a.server_id LEFT JOIN inventory.racks r ON r.id=sv.rack_id
JOIN inventory.network_interfaces sni ON sni.id=a.server_interface_id JOIN inventory.network_devices sw ON sw.id=a.switch_device_id JOIN inventory.network_interfaces swi ON swi.id=a.switch_interface_id
LEFT JOIN inventory.network_vlans v ON v.id=a.vlan_id LEFT JOIN inventory.network_devices c1 ON c1.device_key=s.site_key||'-core-01' LEFT JOIN inventory.network_devices c2 ON c2.device_key=s.site_key||'-core-02'
LEFT JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01' LEFT JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-core-rtr-01';

CREATE OR REPLACE VIEW inventory.data_center_backbone_overview AS
SELECT nl.link_key,ss.site_key source_site_key,ss.name source_site,sd.device_key source_core,nl.source_interface,
 ts.site_key target_site_key,ts.name target_site,td.device_key target_core,nl.target_interface,nl.provider,nl.circuit_id,
 nl.bandwidth_bps,nl.utilization_pct,nl.latency_ms,nl.packet_loss_pct,nl.status,nl.redundancy_group,nl.is_simulated,nl.last_seen_at
FROM inventory.network_links nl JOIN inventory.network_devices sd ON sd.id=nl.source_device_id JOIN inventory.racks sr ON sr.id=sd.rack_id JOIN inventory.data_center_rows sdr ON sdr.id=sr.row_id JOIN inventory.rooms srm ON srm.id=sdr.room_id JOIN inventory.sites ss ON ss.id=srm.site_id
JOIN inventory.network_devices td ON td.id=nl.target_device_id JOIN inventory.racks tr ON tr.id=td.rack_id JOIN inventory.data_center_rows tdr ON tdr.id=tr.row_id JOIN inventory.rooms trm ON trm.id=tdr.room_id JOIN inventory.sites ts ON ts.id=trm.site_id WHERE nl.attributes->>'scope'='inter_data_center';

CREATE OR REPLACE VIEW inventory.end_to_end_connectivity_paths AS
SELECT s.site_key,s.name site_name,rtr.device_key router,fw.device_key firewall,core.device_key l3_switch,v.vlan_key,v.vlan_id,v.vrf_name,v.cidr,
 sv.server_key,sv.hostname server_name,vm.vm_key,vm.name vm_name,kc.cluster_key,kn.name k8s_node,p.name pod_name,p.phase pod_phase,
 a.application_key,a.name application_name,bs.service_key,bs.name business_service,
 CASE WHEN p.phase='Running' AND sv.status='active' AND core.status='active' THEN 'healthy' ELSE 'at_risk' END path_status
FROM inventory.k8s_pods p JOIN inventory.k8s_nodes kn ON kn.id=p.node_id JOIN inventory.virtual_machines vm ON vm.id=kn.vm_id
JOIN inventory.hypervisors h ON h.id=vm.hypervisor_id JOIN inventory.servers sv ON sv.id=h.server_id
JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id JOIN inventory.sites s ON s.id=kc.site_id
JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-core-rtr-01' JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
JOIN inventory.network_devices core ON core.device_key=s.site_key||'-core-01' JOIN inventory.network_vlans v ON v.site_id=s.id AND v.vlan_id=120
LEFT JOIN inventory.topology_relationships pa ON pa.source_type='pod' AND pa.source_id=p.id AND pa.target_type='application'
LEFT JOIN inventory.applications a ON a.id=pa.target_id LEFT JOIN inventory.business_service_applications bsa ON bsa.application_id=a.id LEFT JOIN inventory.business_services bs ON bs.id=bsa.business_service_id;

COMMIT;
