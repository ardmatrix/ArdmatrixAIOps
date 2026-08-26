BEGIN;

-- One inventory-backed summary per data center for the global full-stack map.
CREATE OR REPLACE VIEW inventory.site_full_stack_topology_overview AS
SELECT s.id,s.site_key,s.name site_name,s.region,s.health_status,
       (SELECT count(*) FROM inventory.network_devices nd
        JOIN inventory.racks r ON r.id=nd.rack_id
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id
        WHERE rm.site_id=s.id AND nd.device_type='switch' AND nd.role ILIKE '%core%') core_switches,
       (SELECT count(*) FROM inventory.network_devices nd
        JOIN inventory.racks r ON r.id=nd.rack_id
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id
        WHERE rm.site_id=s.id AND nd.device_type='switch' AND nd.role ILIKE '%access%') access_switches,
       (SELECT count(*) FROM inventory.servers sv
        JOIN inventory.racks r ON r.id=sv.rack_id
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id WHERE rm.site_id=s.id) servers,
       (SELECT count(*) FROM inventory.virtual_machines vm
        JOIN inventory.hypervisors h ON h.id=vm.hypervisor_id
        JOIN inventory.servers sv ON sv.id=h.server_id
        JOIN inventory.racks r ON r.id=sv.rack_id
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id WHERE rm.site_id=s.id) virtual_machines,
       (SELECT count(*) FROM inventory.k8s_clusters kc WHERE kc.site_id=s.id) k8s_clusters,
       (SELECT count(*) FROM inventory.k8s_nodes kn
        JOIN inventory.k8s_clusters kc ON kc.id=kn.cluster_id WHERE kc.site_id=s.id) k8s_nodes,
       (SELECT count(*) FROM inventory.k8s_pods kp
        JOIN inventory.k8s_namespaces ns ON ns.id=kp.namespace_id
        JOIN inventory.k8s_clusters kc ON kc.id=ns.cluster_id WHERE kc.site_id=s.id) k8s_pods,
       (SELECT count(DISTINCT aps.application_id) FROM inventory.application_sites aps
        WHERE aps.site_id=s.id) applications,
       (SELECT count(*) FROM inventory.data_center_backbone_overview d
        WHERE d.source_site_key=s.site_key OR d.target_site_key=s.site_key) dci_links,
       (SELECT count(*) FROM inventory.server_network_attachments a
        WHERE a.site_id=s.id AND a.status='up') active_server_links,
       true AS is_simulated
FROM inventory.sites s;

COMMENT ON VIEW inventory.site_full_stack_topology_overview IS
  'Simulated demo summary used by the global full-stack data-center topology.';

COMMIT;
