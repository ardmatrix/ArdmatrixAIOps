-- Explicit routing-domain inventory for the four-data-center customer demo.
-- Each data center owns four VRFs aligned with its routed VLAN design.
INSERT INTO inventory.network_vrfs
  (id,vrf_key,site_id,name,route_distinguisher,route_count,bgp_neighbor_count,
   bgp_neighbors_up,status,is_simulated,last_converged_at,attributes)
SELECT md5(s.site_key||'-vrf-'||v.name)::uuid,
       s.site_key||'-vrf-'||lower(v.name),s.id,v.name,
       '65000:'||(dense_rank() OVER (ORDER BY s.site_key)*100+v.sequence_no),
       v.route_count,4,4,'active',true,now()-interval '2 minutes',
       jsonb_build_object('routing_protocol','BGP','address_family','IPv4','redundancy','dual-core')
FROM inventory.sites s
CROSS JOIN (VALUES
  (1,'BILLING',42),(2,'PROD',128),(3,'MGMT',56),(4,'SERVICES',38)
) v(sequence_no,name,route_count)
ON CONFLICT (site_id,name) DO UPDATE SET
  route_distinguisher=EXCLUDED.route_distinguisher,
  route_count=EXCLUDED.route_count,
  bgp_neighbor_count=EXCLUDED.bgp_neighbor_count,
  bgp_neighbors_up=EXCLUDED.bgp_neighbors_up,
  status=EXCLUDED.status,
  is_simulated=EXCLUDED.is_simulated,
  last_converged_at=EXCLUDED.last_converged_at,
  attributes=EXCLUDED.attributes,
  updated_at=now();
