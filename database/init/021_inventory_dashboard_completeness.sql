BEGIN;

-- Complete ownership and business context for the four-DC reference estate.
UPDATE inventory.sites
SET owner_id = (SELECT id FROM inventory.owners WHERE owner_key = 'dc-operations')
WHERE owner_id IS NULL;

UPDATE inventory.servers sv
SET owner_id = o.id,
    criticality = CASE (abs(hashtext(sv.server_key)) % 3) WHEN 0 THEN 'critical' WHEN 1 THEN 'high' ELSE 'medium' END,
    business_service = CASE (abs(hashtext(sv.server_key)) % 3)
      WHEN 0 THEN 'Global Billing' WHEN 1 THEN 'Customer Applications' ELSE 'Shared Platform Services' END,
    warranty_expiry = current_date + (180 + abs(hashtext(sv.server_key)) % 1095),
    end_of_support = current_date + (730 + abs(hashtext(sv.server_key)) % 1460)
FROM inventory.owners o
WHERE o.owner_key = CASE (abs(hashtext(sv.server_key)) % 3)
  WHEN 0 THEN 'global-infra-ops' WHEN 1 THEN 'customer-app-team' ELSE 'platform-team' END;

UPDATE inventory.virtual_machines vm
SET owner_id = sv.owner_id,
    snapshot_count = 1 + abs(hashtext(vm.vm_key)) % 4,
    backup_status = CASE WHEN abs(hashtext(vm.vm_key)) % 19 = 0 THEN 'warning' ELSE 'protected' END
FROM inventory.hypervisors h JOIN inventory.servers sv ON sv.id = h.server_id
WHERE vm.hypervisor_id = h.id;

UPDATE inventory.k8s_clusters
SET owner_id = (SELECT id FROM inventory.owners WHERE owner_key = 'platform-team')
WHERE owner_id IS NULL;

UPDATE inventory.applications a
SET owner_id = o.id
FROM inventory.owners o
WHERE a.owner_id IS NULL
  AND o.owner_key = CASE (a.attributes->>'application_index')::int
    WHEN 1 THEN 'global-infra-ops' WHEN 2 THEN 'customer-app-team' ELSE 'platform-team' END;

-- Three meaningful components per application.
INSERT INTO inventory.application_components
  (id,application_id,component_key,name,component_type,version,runtime,listen_endpoints,status,is_simulated)
SELECT md5(a.application_key||'-component-'||c.n)::uuid,a.id,'component-'||c.n,
       a.name||' '||c.component_name,c.component_type,c.version,c.runtime,c.endpoints::jsonb,'active',true
FROM inventory.applications a CROSS JOIN (VALUES
  (1,'Web','web','3.0.2','NGINX 1.27','[{"protocol":"https","port":443}]'),
  (2,'API','api','3.0.5','Java 21 / Spring Boot','[{"protocol":"http","port":8080}]'),
  (3,'Database','database','16.4','PostgreSQL 16','[{"protocol":"tcp","port":5432}]')
) c(n,component_name,component_type,version,runtime,endpoints)
ON CONFLICT (application_id,component_key) DO UPDATE
SET name=excluded.name,component_type=excluded.component_type,version=excluded.version,
    runtime=excluded.runtime,listen_endpoints=excluded.listen_endpoints,status='active';

-- Map every pod to an explicit workload and give it a usable pod address.
INSERT INTO inventory.k8s_workloads
  (id,namespace_id,workload_uid,name,workload_type,desired_replicas,available_replicas,container_images,labels,is_simulated)
SELECT md5(ns.namespace_uid||'-workload-'||w.n)::uuid,ns.id,ns.namespace_uid||'-workload-'||w.n,
       w.name,w.kind,3,
       (SELECT count(*) FROM inventory.k8s_pods p
        WHERE p.namespace_id=ns.id AND (p.labels->>'application_index')::int=w.n AND p.phase='Running'),
       ARRAY[w.image],jsonb_build_object('application_index',w.n,'managed_by','ARDMATRIX simulator'),true
FROM inventory.k8s_namespaces ns CROSS JOIN (VALUES
  (1,'billing-api','Deployment','ardmatrix/billing-api:3.0.5'),
  (2,'customer-application','Deployment','ardmatrix/customer-app:3.0.4'),
  (3,'shared-services','StatefulSet','ardmatrix/shared-services:3.0.2')
) w(n,name,kind,image)
ON CONFLICT (namespace_id,workload_uid) DO UPDATE
SET desired_replicas=excluded.desired_replicas,available_replicas=excluded.available_replicas,
    container_images=excluded.container_images;

UPDATE inventory.k8s_pods p
SET workload_id = w.id,
    pod_ip = format('10.%s.%s.%s',
      60 + CASE s.site_key WHEN 'dc-chicago' THEN 1 WHEN 'dc-london' THEN 2 WHEN 'dc-mumbai' THEN 3 ELSE 4 END,
      50 + (abs(hashtext(c.cluster_key)) % 20),
      10 + (abs(hashtext(p.pod_uid)) % 220))::inet
FROM inventory.k8s_namespaces ns
JOIN inventory.k8s_clusters c ON c.id=ns.cluster_id
JOIN inventory.sites s ON s.id=c.site_id
JOIN inventory.k8s_workloads w ON w.namespace_id=ns.id
WHERE p.namespace_id=ns.id
  AND (w.labels->>'application_index')::int=(p.labels->>'application_index')::int;

INSERT INTO inventory.k8s_containers
  (id,pod_id,container_key,name,image,runtime,cpu_request_millicores,cpu_limit_millicores,
   memory_request_bytes,memory_limit_bytes,status,is_simulated)
SELECT md5(p.pod_uid||'-main')::uuid,p.id,'main',coalesce(w.name,'application')||'-container',
       coalesce(w.container_images[1],'ardmatrix/application:3.0'),'containerd 2.0',250,1000,
       268435456,1073741824,CASE WHEN p.phase='Running' THEN 'running' ELSE 'waiting' END,true
FROM inventory.k8s_pods p LEFT JOIN inventory.k8s_workloads w ON w.id=p.workload_id
ON CONFLICT (pod_id,container_key) DO UPDATE
SET name=excluded.name,image=excluded.image,runtime=excluded.runtime,status=excluded.status;

-- Operational values for the network inventory table.
UPDATE inventory.network_devices nd
SET attributes = nd.attributes || jsonb_build_object(
  'cpu_utilization_pct', 18 + abs(hashtext(nd.device_key)) % 48,
  'memory_utilization_pct', 32 + abs(hashtext(reverse(nd.device_key))) % 42,
  'temperature_c', 31 + abs(hashtext(nd.device_key||'-temp')) % 14,
  'open_alerts', CASE WHEN abs(hashtext(nd.device_key)) % 11 = 0 THEN 1 ELSE 0 END,
  'firmware_compliance', CASE WHEN abs(hashtext(nd.device_key)) % 13 = 0 THEN 'upgrade required' ELSE 'compliant' END,
  'config_backup', 'current',
  'monitoring_status', 'monitored'
);

-- A few open reference alerts make alert counts demonstrable without falsifying every asset.
INSERT INTO events.inventory_alerts
  (alert_key,entity_type,entity_id,severity,status,title,description,metric_name,metric_value,threshold_value,is_simulated)
SELECT 'dashboard-server-'||sv.server_key,'server',sv.id,
       CASE WHEN row_number() OVER (ORDER BY sv.server_key)=1 THEN 'critical' ELSE 'warning' END,
       'open','Simulated infrastructure threshold breach','Reference alert for dashboard validation',
       'cpu_utilization_percent',88,80,true
FROM inventory.servers sv
ORDER BY sv.server_key LIMIT 4
ON CONFLICT (alert_key) DO NOTHING;

INSERT INTO events.inventory_alerts
  (alert_key,entity_type,entity_id,severity,status,title,description,metric_name,metric_value,threshold_value,is_simulated)
SELECT 'dashboard-vm-'||vm.vm_key,'vm',vm.id,'warning','open','Simulated VM capacity warning',
       'Reference alert for dashboard validation','storage_utilization_pct',84,80,true
FROM inventory.virtual_machines vm
ORDER BY vm.vm_key LIMIT 4
ON CONFLICT (alert_key) DO NOTHING;

COMMIT;
