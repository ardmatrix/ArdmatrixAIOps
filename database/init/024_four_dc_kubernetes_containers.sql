-- Container inventory for every pod in the four-data-center reference model.
-- Values are deterministic and explicitly marked as simulated demo data.
INSERT INTO inventory.k8s_containers
  (id,pod_id,container_key,name,image,image_id,runtime,
   cpu_request_millicores,cpu_limit_millicores,
   memory_request_bytes,memory_limit_bytes,gpu_request,status,is_simulated)
SELECT md5(p.pod_uid||'-main')::uuid,p.id,'main',
       CASE
         WHEN p.name ILIKE '%billing%' THEN 'billing-api'
         WHEN p.name ILIKE '%application%' THEN 'application-api'
         ELSE 'shared-services'
       END,
       CASE
         WHEN p.name ILIKE '%billing%' THEN 'registry.ardmatrix.local/finance/billing-api:2.4.1'
         WHEN p.name ILIKE '%application%' THEN 'registry.ardmatrix.local/platform/application-api:3.8.0'
         ELSE 'registry.ardmatrix.local/platform/shared-services:1.7.2'
       END,
       'sha256:'||md5(p.pod_uid||'-image'),
       'containerd://1.7.20',
       CASE WHEN p.name ILIKE '%billing%' THEN 500 ELSE 250 END,
       CASE WHEN p.name ILIKE '%billing%' THEN 2000 ELSE 1000 END,
       CASE WHEN p.name ILIKE '%billing%' THEN 536870912 ELSE 268435456 END,
       CASE WHEN p.name ILIKE '%billing%' THEN 2147483648 ELSE 1073741824 END,
       0,CASE WHEN p.phase='Running' THEN 'running' ELSE 'waiting' END,true
FROM inventory.k8s_pods p
ON CONFLICT (pod_id,container_key) DO UPDATE SET
  name=EXCLUDED.name,image=EXCLUDED.image,image_id=EXCLUDED.image_id,
  runtime=EXCLUDED.runtime,cpu_request_millicores=EXCLUDED.cpu_request_millicores,
  cpu_limit_millicores=EXCLUDED.cpu_limit_millicores,
  memory_request_bytes=EXCLUDED.memory_request_bytes,
  memory_limit_bytes=EXCLUDED.memory_limit_bytes,gpu_request=EXCLUDED.gpu_request,
  status=EXCLUDED.status,is_simulated=EXCLUDED.is_simulated,updated_at=now();

-- Add a service-mesh sidecar to one pod per Kubernetes node to demonstrate
-- multi-container pod visibility without overcrowding the inventory table.
WITH ranked_pods AS (
  SELECT p.*,row_number() OVER (PARTITION BY p.node_id ORDER BY p.pod_uid) AS node_rank
  FROM inventory.k8s_pods p
)
INSERT INTO inventory.k8s_containers
  (id,pod_id,container_key,name,image,image_id,runtime,
   cpu_request_millicores,cpu_limit_millicores,
   memory_request_bytes,memory_limit_bytes,gpu_request,status,is_simulated)
SELECT md5(p.pod_uid||'-mesh-proxy')::uuid,p.id,'mesh-proxy','envoy-proxy',
       'docker.io/envoyproxy/envoy:v1.31.2','sha256:'||md5(p.pod_uid||'-envoy-image'),
       'containerd://1.7.20',100,500,134217728,536870912,0,
       CASE WHEN p.phase='Running' THEN 'running' ELSE 'waiting' END,true
FROM ranked_pods p
WHERE p.node_rank=1
ON CONFLICT (pod_id,container_key) DO UPDATE SET
  image=EXCLUDED.image,image_id=EXCLUDED.image_id,runtime=EXCLUDED.runtime,
  status=EXCLUDED.status,is_simulated=EXCLUDED.is_simulated,updated_at=now();
