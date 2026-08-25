BEGIN;

-- Deterministic simulated inventory for development and dashboard validation.
-- These records describe containment only; cross-domain topology is intentionally deferred.
INSERT INTO inventory.discovery_sources (id, source_key, name, source_type, is_simulated)
VALUES ('00000000-0000-0000-0000-000000000001', 'demo-simulator', 'ARDMATRIX Demo Simulator', 'simulator', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.owners (id, owner_key, name, owner_type, contact_email)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'dc-operations', 'Data Center Operations', 'team', 'dc-ops@example.invalid'),
  ('10000000-0000-0000-0000-000000000002', 'platform-team', 'Platform Engineering', 'team', 'platform@example.invalid'),
  ('10000000-0000-0000-0000-000000000003', 'crm-team', 'CRM Application Team', 'team', 'crm@example.invalid')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.sites
  (id, site_key, name, timezone, owner_id, source_id, source_native_id, is_simulated, address)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'dc-mumbai', 'Mumbai Data Center', 'Asia/Kolkata',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'site-mum', true,
   '{"city":"Mumbai","country":"India"}'),
  ('20000000-0000-0000-0000-000000000002', 'dc-bengaluru', 'Bengaluru Data Center', 'Asia/Kolkata',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'site-blr', true,
   '{"city":"Bengaluru","country":"India"}'),
  ('20000000-0000-0000-0000-000000000003', 'dc-delhi', 'Delhi Data Center', 'Asia/Kolkata',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'site-del', true,
   '{"city":"Delhi","country":"India"}')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.rooms (id, site_id, room_key, name, is_simulated)
VALUES
  ('21000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'room-a', 'Mumbai Hall A', true),
  ('21000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'room-a', 'Bengaluru Hall A', true),
  ('21000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', 'room-a', 'Delhi Hall A', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.data_center_rows (id, room_id, row_key, name, is_simulated)
VALUES
  ('22000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'row-a', 'Row A', true),
  ('22000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000002', 'row-a', 'Row A', true),
  ('22000000-0000-0000-0000-000000000003', '21000000-0000-0000-0000-000000000003', 'row-a', 'Row A', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.racks (id, row_id, rack_key, name, rack_units, max_power_watts, is_simulated)
VALUES
  ('23000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'rack-a01', 'MUM-A01', 42, 12000, true),
  ('23000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000002', 'rack-a01', 'BLR-A01', 42, 12000, true),
  ('23000000-0000-0000-0000-000000000003', '22000000-0000-0000-0000-000000000003', 'rack-a01', 'DEL-A01', 42, 12000, true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.servers
  (id, server_key, hostname, rack_id, rack_unit_start, rack_unit_height, server_type, manufacturer, model,
   serial_number, architecture, operating_system, operating_system_version, status, owner_id, source_id,
   source_native_id, is_simulated)
VALUES
  ('30000000-0000-0000-0000-000000000001', 'srv-mum-001', 'srv-mum-001', '23000000-0000-0000-0000-000000000001', 10, 2,
   'physical', 'Dell', 'PowerEdge R750', 'SIM-MUM-001', 'x86_64', 'Ubuntu Linux', '24.04', 'active',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'server-mum-001', true),
  ('30000000-0000-0000-0000-000000000002', 'srv-blr-001', 'srv-blr-001', '23000000-0000-0000-0000-000000000002', 10, 2,
   'physical', 'HPE', 'ProLiant DL380 Gen11', 'SIM-BLR-001', 'x86_64', 'VMware ESXi', '8.0', 'active',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'server-blr-001', true),
  ('30000000-0000-0000-0000-000000000003', 'srv-del-gpu-001', 'srv-del-gpu-001', '23000000-0000-0000-0000-000000000003', 10, 4,
   'physical', 'Lenovo', 'ThinkSystem SR675 V3', 'SIM-DEL-001', 'x86_64', 'Ubuntu Linux', '24.04', 'active',
   '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'server-del-001', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.cpu_devices
  (id, server_id, socket_index, manufacturer, model, architecture, physical_cores, logical_processors, base_frequency_mhz, max_frequency_mhz)
VALUES
  ('31000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 0, 'Intel', 'Xeon Gold 6330', 'x86_64', 28, 56, 2000, 3100),
  ('31000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 0, 'Intel', 'Xeon Gold 5416S', 'x86_64', 16, 32, 2000, 4000),
  ('31000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', 0, 'AMD', 'EPYC 9554', 'x86_64', 64, 128, 3100, 3750)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.memory_modules
  (id, server_id, slot, manufacturer, memory_type, capacity_bytes, speed_mts, ecc)
VALUES
  ('32000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'A1', 'Samsung', 'DDR4', 68719476736, 3200, true),
  ('32000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 'A2', 'Samsung', 'DDR4', 68719476736, 3200, true),
  ('32000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000002', 'A1', 'Micron', 'DDR5', 137438953472, 4800, true),
  ('32000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000003', 'A1', 'Micron', 'DDR5', 274877906944, 4800, true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.gpu_devices
  (id, server_id, device_index, manufacturer, model, pci_address, vram_bytes, driver_version, compute_capability)
VALUES
  ('33000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', 0,
   'NVIDIA', 'L40S', '0000:41:00.0', 51539607552, '550.90', '8.9')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.storage_devices
  (id, server_id, device_name, manufacturer, model, media_type, interface_type, capacity_bytes, status)
VALUES
  ('34000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'nvme0n1', 'Samsung', 'PM9A3', 'nvme', 'PCIe', 3840755982336, 'active'),
  ('34000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'naa.6000c29', 'HPE', 'Smart Array Virtual Disk', 'virtual', 'SAS', 7681511964672, 'active'),
  ('34000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', 'nvme0n1', 'Samsung', 'PM1743', 'nvme', 'PCIe', 7681511964672, 'active')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.network_devices
  (id, device_key, hostname, rack_id, device_type, role, manufacturer, model, serial_number, management_address,
   owner_id, source_id, source_native_id, is_simulated)
VALUES
  ('40000000-0000-0000-0000-000000000001', 'sw-mum-access-01', 'sw-mum-access-01', '23000000-0000-0000-0000-000000000001',
   'switch', 'access', 'Cisco', 'Nexus 93180YC-FX3', 'SIM-SW-MUM-001', '10.10.0.11',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'switch-mum-001', true),
  ('40000000-0000-0000-0000-000000000002', 'sw-blr-access-01', 'sw-blr-access-01', '23000000-0000-0000-0000-000000000002',
   'switch', 'access', 'Arista', '7050SX3', 'SIM-SW-BLR-001', '10.20.0.11',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'switch-blr-001', true),
  ('40000000-0000-0000-0000-000000000003', 'fw-del-01', 'fw-del-01', '23000000-0000-0000-0000-000000000003',
   'firewall', 'perimeter', 'Palo Alto Networks', 'PA-3410', 'SIM-FW-DEL-001', '10.30.0.11',
   '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'firewall-del-001', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.network_interfaces
  (id, server_id, network_device_id, interface_name, interface_type, mac_address, ip_addresses, mtu, speed_bps, administrative_status)
VALUES
  ('41000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', NULL, 'eno1', 'ethernet', '02:00:00:00:01:01', ARRAY['10.10.10.11'::inet], 1500, 25000000000, 'up'),
  ('41000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', NULL, 'vmnic0', 'ethernet', '02:00:00:00:02:01', ARRAY['10.20.10.11'::inet], 9000, 25000000000, 'up'),
  ('41000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', NULL, 'eno1', 'ethernet', '02:00:00:00:03:01', ARRAY['10.30.10.11'::inet], 9000, 100000000000, 'up'),
  ('41000000-0000-0000-0000-000000000011', NULL, '40000000-0000-0000-0000-000000000001', 'Ethernet1/1', 'ethernet', NULL, '{}', 9216, 25000000000, 'up'),
  ('41000000-0000-0000-0000-000000000012', NULL, '40000000-0000-0000-0000-000000000002', 'Ethernet1', 'ethernet', NULL, '{}', 9216, 25000000000, 'up')
ON CONFLICT DO NOTHING;

INSERT INTO inventory.network_segments
  (id, site_id, segment_key, name, segment_type, vlan_id, cidr, gateway, is_simulated)
VALUES
  ('42000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'mum-server-vlan', 'Mumbai Server VLAN', 'vlan', 110, '10.10.10.0/24', '10.10.10.1', true),
  ('42000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'blr-server-vlan', 'Bengaluru Server VLAN', 'vlan', 120, '10.20.10.0/24', '10.20.10.1', true),
  ('42000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', 'del-server-vlan', 'Delhi Server VLAN', 'vlan', 130, '10.30.10.0/24', '10.30.10.1', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.storage_systems
  (id, storage_key, name, site_id, rack_id, storage_type, manufacturer, model, serial_number,
   raw_capacity_bytes, usable_capacity_bytes, management_address, source_id, is_simulated)
VALUES
  ('43000000-0000-0000-0000-000000000001', 'san-mum-01', 'Mumbai Primary SAN',
   '20000000-0000-0000-0000-000000000001', '23000000-0000-0000-0000-000000000001', 'san',
   'Dell', 'PowerStore 1200T', 'SIM-SAN-MUM-001', 109951162777600, 87960930222080, '10.10.0.21',
   '00000000-0000-0000-0000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.hypervisors
  (id, hypervisor_key, server_id, hypervisor_type, version, cluster_name, source_id, is_simulated)
VALUES
  ('50000000-0000-0000-0000-000000000001', 'esxi-blr-001', '30000000-0000-0000-0000-000000000002',
   'VMware ESXi', '8.0', 'BLR-Compute', '00000000-0000-0000-0000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.virtual_machines
  (id, vm_key, name, hostname, hypervisor_id, vcpu_count, memory_bytes, provisioned_storage_bytes,
   operating_system, operating_system_version, ip_addresses, owner_id, source_id, source_native_id, is_simulated)
VALUES
  ('51000000-0000-0000-0000-000000000001', 'vm-crm-k8s-01', 'CRM Kubernetes Node 1', 'vm-crm-k8s-01',
   '50000000-0000-0000-0000-000000000001', 8, 34359738368, 536870912000, 'Ubuntu Linux', '24.04',
   ARRAY['10.20.10.101'::inet], '10000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000001', 'vm-crm-k8s-01', true),
  ('51000000-0000-0000-0000-000000000002', 'vm-crm-db-01', 'CRM Database', 'vm-crm-db-01',
   '50000000-0000-0000-0000-000000000001', 8, 68719476736, 1099511627776, 'Rocky Linux', '9',
   ARRAY['10.20.10.110'::inet], '10000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000001', 'vm-crm-db-01', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_clusters
  (id, cluster_key, name, site_id, distribution, version, status, owner_id, source_id, source_native_id, is_simulated)
VALUES
  ('60000000-0000-0000-0000-000000000001', 'k8s-crm-prod', 'CRM Production Cluster',
   '20000000-0000-0000-0000-000000000002', 'k3s', 'v1.33', 'active',
   '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'k8s-crm-prod', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_nodes
  (id, cluster_id, node_uid, name, vm_id, role, architecture, operating_system, kubelet_version,
   cpu_capacity_millicores, memory_capacity_bytes, status, labels, is_simulated)
VALUES
  ('61000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'node-uid-01', 'crm-worker-01',
   '51000000-0000-0000-0000-000000000001', 'worker', 'amd64', 'linux', 'v1.33', 8000, 34359738368, 'ready',
   '{"workload":"crm","zone":"blr-a"}', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_namespaces (id, cluster_id, namespace_uid, name, labels, is_simulated)
VALUES
  ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'namespace-uid-crm', 'crm',
   '{"environment":"production"}', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_workloads
  (id, namespace_id, workload_uid, name, workload_type, desired_replicas, available_replicas, container_images, labels, is_simulated)
VALUES
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 'deployment-uid-web',
   'crm-web', 'Deployment', 2, 2, ARRAY['ardmatrix/crm-web:1.0'], '{"app":"crm-web"}', true),
  ('63000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000001', 'deployment-uid-api',
   'crm-api', 'Deployment', 2, 2, ARRAY['ardmatrix/crm-api:1.0'], '{"app":"crm-api"}', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_services
  (id, namespace_id, service_uid, name, service_type, cluster_ip, ports, selector, is_simulated)
VALUES
  ('64000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 'service-uid-web',
   'crm-web', 'ClusterIP', '10.43.10.10', '[{"name":"http","port":80,"targetPort":8080}]', '{"app":"crm-web"}', true),
  ('64000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000001', 'service-uid-api',
   'crm-api', 'ClusterIP', '10.43.10.20', '[{"name":"http","port":8080,"targetPort":8080}]', '{"app":"crm-api"}', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_pods
  (id, namespace_id, node_id, workload_id, pod_uid, name, phase, pod_ip, qos_class, restart_policy, labels, is_simulated)
VALUES
  ('65000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001',
   '63000000-0000-0000-0000-000000000001', 'pod-uid-web-01', 'crm-web-01', 'Running', '10.42.0.11', 'Burstable', 'Always', '{"app":"crm-web"}', true),
  ('65000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001',
   '63000000-0000-0000-0000-000000000002', 'pod-uid-api-01', 'crm-api-01', 'Running', '10.42.0.21', 'Burstable', 'Always', '{"app":"crm-api"}', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.k8s_containers
  (id, pod_id, container_key, name, image, runtime, cpu_request_millicores, cpu_limit_millicores,
   memory_request_bytes, memory_limit_bytes, status, is_simulated)
VALUES
  ('66000000-0000-0000-0000-000000000001', '65000000-0000-0000-0000-000000000001', 'crm-web', 'crm-web',
   'ardmatrix/crm-web:1.0', 'containerd', 200, 1000, 268435456, 1073741824, 'running', true),
  ('66000000-0000-0000-0000-000000000002', '65000000-0000-0000-0000-000000000002', 'crm-api', 'crm-api',
   'ardmatrix/crm-api:1.0', 'containerd', 500, 2000, 536870912, 2147483648, 'running', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.business_services
  (id, service_key, name, description, criticality, service_tier, owner_id, is_simulated)
VALUES
  ('70000000-0000-0000-0000-000000000001', 'crm-business-service', 'CRM Business Service',
   'Customer relationship management business capability', 'critical', 'tier-1',
   '10000000-0000-0000-0000-000000000003', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.applications
  (id, application_key, name, description, application_type, version, environment, criticality, owner_id, source_id, is_simulated)
VALUES
  ('71000000-0000-0000-0000-000000000001', 'crm-application', 'CRM Application',
   'Customer-facing CRM demonstration application', 'three-tier', '1.0', 'production', 'critical',
   '10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.application_components
  (id, application_id, component_key, name, component_type, version, runtime, listen_endpoints, is_simulated)
VALUES
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'crm-web', 'CRM Web', 'web', '1.0', 'nginx', '[{"port":8080,"protocol":"http"}]', true),
  ('72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001', 'crm-api', 'CRM API', 'api', '1.0', 'python', '[{"port":8080,"protocol":"http"}]', true),
  ('72000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000001', 'crm-db', 'CRM Database', 'database', '17', 'postgresql', '[{"port":5432,"protocol":"tcp"}]', true)
ON CONFLICT DO NOTHING;

INSERT INTO inventory.inventory_changes
  (entity_type, entity_id, change_type, source_id, is_simulated, current_values)
SELECT 'site', id, 'discovered', '00000000-0000-0000-0000-000000000001', true,
       jsonb_build_object('site_key', site_key, 'name', name)
FROM inventory.sites
WHERE is_simulated
  AND NOT EXISTS (
      SELECT 1 FROM inventory.inventory_changes c
      WHERE c.entity_type = 'site' AND c.entity_id = sites.id AND c.change_type = 'discovered'
  );

COMMIT;
