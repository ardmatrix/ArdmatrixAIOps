BEGIN;

CREATE TABLE IF NOT EXISTS inventory.business_service_applications (
  business_service_id uuid NOT NULL REFERENCES inventory.business_services(id) ON DELETE CASCADE,
  application_id uuid NOT NULL REFERENCES inventory.applications(id) ON DELETE CASCADE,
  relationship_type text NOT NULL DEFAULT 'supports',
  is_simulated boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_service_id,application_id)
);

ALTER TABLE inventory.application_sites
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'hosting',
  ADD COLUMN IF NOT EXISTS is_simulated boolean NOT NULL DEFAULT false;

INSERT INTO inventory.business_services
  (id,service_key,name,description,criticality,service_tier,owner_id,status,is_simulated)
VALUES
  (md5('business-payments')::uuid,'payments-service','Digital Payments','Payment authorization and settlement','critical','tier-1',(SELECT id FROM inventory.owners WHERE owner_key='global-infra-ops'),'active',true),
  (md5('business-customer')::uuid,'customer-service','Customer Experience','Customer portals and engagement','high','tier-1',(SELECT id FROM inventory.owners WHERE owner_key='crm-team'),'active',true),
  (md5('business-analytics')::uuid,'analytics-service','Enterprise Analytics','Reporting and decision support','high','tier-2',(SELECT id FROM inventory.owners WHERE owner_key='platform-team'),'active',true),
  (md5('business-operations')::uuid,'operations-service','Operations Platform','Internal operational workflows','medium','tier-2',(SELECT id FROM inventory.owners WHERE owner_key='global-infra-ops'),'active',true)
ON CONFLICT (service_key) DO UPDATE SET name=excluded.name,criticality=excluded.criticality,status='active';

INSERT INTO inventory.k8s_clusters
  (id,cluster_key,name,site_id,distribution,version,api_endpoint,status,owner_id,source_id,source_native_id,is_simulated)
SELECT md5('cluster-'||s.site_key)::uuid,'k8s-'||s.site_key,
       upper(replace(s.site_key,'dc-',''))||' Platform Cluster',s.id,
       CASE length(s.site_key)%3 WHEN 0 THEN 'OpenShift' WHEN 1 THEN 'Rancher Kubernetes' ELSE 'k3s' END,
       'v1.33','https://k8s-'||s.site_key||'.example.invalid:6443',
       CASE WHEN s.health_status='critical' THEN 'degraded' ELSE 'active' END,
       coalesce(s.owner_id,(SELECT id FROM inventory.owners WHERE owner_key='platform-team')),
       (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),'cluster-'||s.site_key,true
FROM inventory.sites s
ON CONFLICT (cluster_key) DO UPDATE SET status=excluded.status,version=excluded.version,last_seen_at=now();

INSERT INTO inventory.k8s_nodes
  (id,cluster_id,node_uid,name,server_id,role,architecture,operating_system,kernel_version,kubelet_version,
   cpu_capacity_millicores,memory_capacity_bytes,gpu_capacity,status,labels,is_simulated)
SELECT md5('k8s-node-'||c.cluster_key||'-'||g)::uuid,c.id,'node-'||c.cluster_key||'-'||g,
       replace(c.cluster_key,'k8s-','')||'-worker-'||g,sv.id,
       CASE WHEN g=1 THEN 'control_plane_worker' ELSE 'worker' END,'amd64','linux','6.8','v1.33',
       16000,68719476736,0,CASE WHEN (g+length(c.cluster_key))%11=0 THEN 'not_ready' ELSE 'ready' END,
       jsonb_build_object('zone',s.site_key||'-a','environment',s.environment),true
FROM inventory.k8s_clusters c JOIN inventory.sites s ON s.id=c.site_id
CROSS JOIN generate_series(1,2) g
JOIN LATERAL (SELECT x.id FROM inventory.servers x JOIN inventory.racks r ON r.id=x.rack_id
 JOIN inventory.data_center_rows dr ON dr.id=r.row_id JOIN inventory.rooms rm ON rm.id=dr.room_id
 WHERE rm.site_id=s.id ORDER BY x.server_key OFFSET g-1 LIMIT 1) sv ON true
WHERE c.cluster_key LIKE 'k8s-dc-%' OR c.cluster_key='k8s-customer-dc-01'
ON CONFLICT (cluster_id,node_uid) DO UPDATE SET status=excluded.status,last_seen_at=now();

INSERT INTO inventory.k8s_namespaces
  (id,cluster_id,namespace_uid,name,status,labels,is_simulated)
SELECT md5('namespace-'||c.cluster_key||'-'||n)::uuid,c.id,'namespace-'||c.cluster_key||'-'||n,n,'active',
       jsonb_build_object('environment',CASE n WHEN 'production' THEN 'production' ELSE 'shared' END),true
FROM inventory.k8s_clusters c CROSS JOIN (VALUES ('production'),('platform'),('monitoring')) names(n)
ON CONFLICT (cluster_id,namespace_uid) DO UPDATE SET status='active';

INSERT INTO inventory.k8s_workloads
  (id,namespace_id,workload_uid,name,workload_type,desired_replicas,available_replicas,container_images,labels,is_simulated)
SELECT md5('workload-'||ns.namespace_uid||'-'||g)::uuid,ns.id,'workload-'||ns.namespace_uid||'-'||g,
       CASE ns.name WHEN 'monitoring' THEN 'observability' WHEN 'platform' THEN 'platform-api' ELSE 'customer-api' END||'-'||g,
       CASE WHEN g=2 AND ns.name='monitoring' THEN 'DaemonSet' ELSE 'Deployment' END,2,
       CASE WHEN (g+length(ns.namespace_uid))%13=0 THEN 1 ELSE 2 END,
       ARRAY['ardmatrix/'||ns.name||'-service:'||g||'.0'],jsonb_build_object('app',ns.name||'-service-'||g),true
FROM inventory.k8s_namespaces ns CROSS JOIN generate_series(1,2) g
ON CONFLICT (namespace_id,workload_uid) DO UPDATE SET available_replicas=excluded.available_replicas;

INSERT INTO inventory.k8s_pods
  (id,namespace_id,node_id,workload_id,pod_uid,name,phase,pod_ip,qos_class,restart_policy,labels,is_simulated)
SELECT md5('pod-'||w.workload_uid||'-'||g)::uuid,w.namespace_id,n.id,w.id,'pod-'||w.workload_uid||'-'||g,
       w.name||'-'||g,CASE WHEN (g+length(w.workload_uid))%17=0 THEN 'Pending' ELSE 'Running' END,NULL,
       'Burstable','Always',w.labels,true
FROM inventory.k8s_workloads w JOIN inventory.k8s_namespaces ns ON ns.id=w.namespace_id
JOIN inventory.k8s_clusters c ON c.id=ns.cluster_id CROSS JOIN generate_series(1,2) g
JOIN LATERAL (SELECT kn.id FROM inventory.k8s_nodes kn WHERE kn.cluster_id=c.id ORDER BY kn.name OFFSET (g-1)%2 LIMIT 1) n ON true
ON CONFLICT (namespace_id,pod_uid) DO UPDATE SET phase=excluded.phase,last_seen_at=now();

INSERT INTO inventory.k8s_containers
  (id,pod_id,container_key,name,image,runtime,cpu_request_millicores,cpu_limit_millicores,
   memory_request_bytes,memory_limit_bytes,status,is_simulated)
SELECT md5('container-'||p.pod_uid)::uuid,p.id,'main','main',w.container_images[1],'containerd',250,1000,
       268435456,1073741824,CASE WHEN p.phase='Running' THEN 'running' ELSE 'waiting' END,true
FROM inventory.k8s_pods p LEFT JOIN inventory.k8s_workloads w ON w.id=p.workload_id
ON CONFLICT (pod_id,container_key) DO UPDATE SET image=excluded.image,status=excluded.status;

INSERT INTO inventory.applications
  (id,application_key,name,description,application_type,version,environment,criticality,owner_id,source_id,status,is_simulated,attributes)
SELECT md5('application-'||s.site_key||'-'||g)::uuid,'app-'||s.site_key||'-'||g,
       upper(replace(s.site_key,'dc-',''))||' '||CASE g WHEN 1 THEN 'Customer Portal' ELSE 'Operations API' END,
       'Deterministic simulated application for technical inventory','microservices','2.'||g,s.environment,
       CASE g WHEN 1 THEN 'critical' ELSE 'high' END,
       coalesce(s.owner_id,(SELECT id FROM inventory.owners WHERE owner_key='platform-team')),
       (SELECT id FROM inventory.discovery_sources WHERE source_key='demo-simulator'),
       CASE WHEN s.health_status='critical' AND g=1 THEN 'maintenance' ELSE 'active' END,true,
       jsonb_build_object('site_key',s.site_key,'monitoring_status','monitored')
FROM inventory.sites s CROSS JOIN generate_series(1,2) g
ON CONFLICT (application_key) DO UPDATE SET status=excluded.status,criticality=excluded.criticality;

INSERT INTO inventory.application_sites (application_id,site_id,role,is_primary,is_simulated)
SELECT a.id,s.id,'primary',true,a.is_simulated FROM inventory.applications a JOIN inventory.sites s ON s.site_key=a.attributes->>'site_key'
ON CONFLICT (application_id,site_id) DO UPDATE SET role='primary',is_primary=true;

INSERT INTO inventory.application_components
  (id,application_id,component_key,name,component_type,version,runtime,listen_endpoints,status,is_simulated)
SELECT md5('component-'||a.application_key||'-'||g)::uuid,a.id,'component-'||g,
       CASE g WHEN 1 THEN a.name||' Web/API' ELSE a.name||' Database' END,
       CASE g WHEN 1 THEN 'api' ELSE 'database' END,'2.'||g,
       CASE g WHEN 1 THEN 'python' ELSE 'postgresql' END,
       CASE g WHEN 1 THEN '[{"port":8080,"protocol":"http"}]'::jsonb ELSE '[{"port":5432,"protocol":"tcp"}]'::jsonb END,
       'active',true
FROM inventory.applications a CROSS JOIN generate_series(1,2) g WHERE a.application_key LIKE 'app-%'
ON CONFLICT (application_id,component_key) DO UPDATE SET version=excluded.version,status='active';

INSERT INTO inventory.business_service_applications (business_service_id,application_id,relationship_type,is_simulated)
SELECT bs.id,a.id,'supports',true FROM inventory.applications a
JOIN LATERAL (SELECT id FROM inventory.business_services ORDER BY service_key OFFSET abs(hashtext(a.application_key))%greatest((SELECT count(*) FROM inventory.business_services),1) LIMIT 1) bs ON true
ON CONFLICT (business_service_id,application_id) DO NOTHING;

COMMIT;
