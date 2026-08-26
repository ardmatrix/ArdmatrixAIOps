BEGIN;

-- Add realistic routed and switched virtual interfaces to the L3 core pair.
WITH numbered_devices AS (
  SELECT nd.id,nd.device_key,s.site_key,dense_rank() OVER (ORDER BY s.site_key) site_no,
         CASE WHEN nd.device_key LIKE '%-core-01' THEN 2 ELSE 3 END host_no
  FROM inventory.network_devices nd
  JOIN inventory.racks r ON r.id=nd.rack_id
  JOIN inventory.data_center_rows dr ON dr.id=r.row_id
  JOIN inventory.rooms rm ON rm.id=dr.room_id
  JOIN inventory.sites s ON s.id=rm.site_id
  WHERE nd.device_key IN (s.site_key||'-core-01',s.site_key||'-core-02')
), interfaces AS (
  SELECT d.*,x.interface_name,x.interface_type,x.ip_address,x.description,x.mtu,x.speed
  FROM numbered_devices d
  CROSS JOIN LATERAL (VALUES
    ('Loopback0','loopback',format('10.255.%s.%s/32',d.site_no,d.host_no),'Routing ID / management loopback',65535,1000000000::bigint),
    ('Vlan110','svi',format('10.%s.10.%s/24',d.site_no+40,d.host_no),'Production server default-gateway SVI',9216,100000000000::bigint),
    ('Vlan130','svi',format('10.%s.30.%s/24',d.site_no+40,d.host_no),'Kubernetes network default-gateway SVI',9216,100000000000::bigint),
    ('Vlan199','svi',format('10.%s.99.%s/24',d.site_no+40,d.host_no),'Infrastructure management SVI',1500,10000000000::bigint)
  ) x(interface_name,interface_type,ip_address,description,mtu,speed)
)
INSERT INTO inventory.network_interfaces
  (network_device_id,interface_name,interface_type,ip_addresses,mtu,speed_bps,administrative_status,attributes)
SELECT id,interface_name,interface_type,ARRAY[ip_address::inet],mtu,speed,'up',
       jsonb_build_object('description',description,'operational_status','up','rx_utilization_pct',
                          (abs(hashtext(device_key||interface_name))%4200)/100.0,'tx_utilization_pct',
                          (abs(hashtext(interface_name||device_key))%3900)/100.0,'errors',0,'layer',3)
FROM interfaces
ON CONFLICT DO NOTHING;

-- Assign /30 transit addresses on router-to-firewall routed links.
WITH devices AS (
  SELECT s.site_key,dense_rank() OVER (ORDER BY s.site_key) site_no,rtr.id router_id,fw.id firewall_id
  FROM inventory.sites s
  JOIN inventory.network_devices rtr ON rtr.device_key=s.site_key||'-wan-rtr-01'
  JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
)
UPDATE inventory.network_interfaces ni
SET ip_addresses=ARRAY[format('172.20.%s.1/30',d.site_no)::inet],
    attributes=ni.attributes||jsonb_build_object('description','Routed transit to edge firewall','layer',3,'operational_status','up'),
    updated_at=now()
FROM devices d
WHERE ni.network_device_id=d.router_id AND ni.interface_name='TenGigabitEthernet0/0/1';

WITH devices AS (
  SELECT s.site_key,dense_rank() OVER (ORDER BY s.site_key) site_no,fw.id firewall_id
  FROM inventory.sites s
  JOIN inventory.network_devices fw ON fw.device_key=s.site_key||'-edge-fw-01'
)
UPDATE inventory.network_interfaces ni
SET ip_addresses=ARRAY[format('172.20.%s.2/30',d.site_no)::inet],
    attributes=ni.attributes||jsonb_build_object('description','Routed transit to WAN router','layer',3,'operational_status','up'),
    updated_at=now()
FROM devices d
WHERE ni.network_device_id=d.firewall_id AND ni.interface_name='Ethernet1/49';

-- Mark intentionally unnumbered interfaces explicitly as Layer 2.
UPDATE inventory.network_interfaces
SET attributes=attributes||jsonb_build_object('layer',2,'ip_assignment','not_applicable_layer_2'),updated_at=now()
WHERE cardinality(ip_addresses)=0 AND coalesce(attributes->>'layer','')='';

COMMIT;
