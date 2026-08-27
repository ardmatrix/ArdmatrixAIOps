BEGIN;

-- Customer-demo DCI full mesh: every pair of the four reference data centers
-- has two carrier- and core-diverse 40 Gbps paths. Telemetry is simulated.
WITH reference_sites AS (
  SELECT id, site_key
  FROM inventory.sites
  WHERE site_key IN ('dc-chicago','dc-london','dc-singapore','dc-mumbai')
), site_pairs AS (
  SELECT a.site_key source_site, b.site_key target_site
  FROM reference_sites a
  JOIN reference_sites b ON a.site_key < b.site_key
), endpoints AS (
  SELECT p.*,
         s1.id source_core_a, s2.id source_core_b,
         t1.id target_core_a, t2.id target_core_b
  FROM site_pairs p
  JOIN inventory.network_devices s1 ON s1.device_key=p.source_site||'-core-rtr-01'
  JOIN inventory.network_devices s2 ON s2.device_key=p.source_site||'-core-rtr-02'
  JOIN inventory.network_devices t1 ON t1.device_key=p.target_site||'-core-rtr-01'
  JOIN inventory.network_devices t2 ON t2.device_key=p.target_site||'-core-rtr-02'
), diverse_links AS (
  SELECT source_site||':'||target_site||':dci-a' link_key,
         source_core_a source_device_id, target_core_a target_device_id,
         'Ethernet1/53' source_interface, 'Ethernet1/54' target_interface,
         'Airtel' provider, 'A' path_name
  FROM endpoints
  UNION ALL
  SELECT source_site||':'||target_site||':dci-b',
         source_core_b, target_core_b,
         'Ethernet1/53', 'Ethernet1/54',
         'Tata Communications', 'B'
  FROM endpoints
)
INSERT INTO inventory.network_links
  (link_key,source_device_id,source_interface,target_device_id,target_interface,
   link_type,provider,circuit_id,bandwidth_bps,utilization_pct,latency_ms,
   packet_loss_pct,status,redundancy_group,is_simulated,last_seen_at,attributes)
SELECT l.link_key,l.source_device_id,l.source_interface,l.target_device_id,l.target_interface,
       'wan',l.provider,'DCI-'||upper(substr(md5(l.link_key),1,10))||'-'||l.path_name,
       40000000000,
       18+(abs(hashtext(l.link_key))%4100)/100.0,
       5+(abs(hashtext(reverse(l.link_key)))%1700)/100.0,
       (abs(hashtext(l.link_key||':loss'))%15)/1000.0,
       'up',split_part(l.link_key,':',1)||':'||split_part(l.link_key,':',2)||':dci',
       true,now()-interval '1 minute',
       jsonb_build_object('scope','inter_data_center','topology','full_mesh',
                          'path',l.path_name,'routing_protocol','eBGP',
                          'encryption','MACsec','discovery_method','simulated_dci')
FROM diverse_links l
ON CONFLICT (link_key) DO UPDATE SET
  source_device_id=excluded.source_device_id,
  target_device_id=excluded.target_device_id,
  source_interface=excluded.source_interface,
  target_interface=excluded.target_interface,
  provider=excluded.provider,
  circuit_id=excluded.circuit_id,
  bandwidth_bps=excluded.bandwidth_bps,
  utilization_pct=excluded.utilization_pct,
  latency_ms=excluded.latency_ms,
  packet_loss_pct=excluded.packet_loss_pct,
  status=excluded.status,
  redundancy_group=excluded.redundancy_group,
  attributes=excluded.attributes,
  last_seen_at=excluded.last_seen_at,
  updated_at=now();

-- Remove legacy reverse-direction ring records where the same unordered site
-- pair is now represented by the canonical full-mesh pair above.
DELETE FROM inventory.network_links
WHERE attributes->>'scope'='inter_data_center'
  AND split_part(link_key,':',1) > split_part(link_key,':',2)
  AND split_part(link_key,':',1) IN ('dc-chicago','dc-london','dc-singapore','dc-mumbai')
  AND split_part(link_key,':',2) IN ('dc-chicago','dc-london','dc-singapore','dc-mumbai');

COMMIT;
