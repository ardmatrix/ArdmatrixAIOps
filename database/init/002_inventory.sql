BEGIN;

CREATE OR REPLACE FUNCTION inventory.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TABLE inventory.discovery_sources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_key text NOT NULL UNIQUE,
    name text NOT NULL,
    source_type text NOT NULL CHECK (source_type IN
        ('manual','api','ssh','snmp','agent','kubernetes','file','simulator')),
    is_simulated boolean NOT NULL DEFAULT false,
    enabled boolean NOT NULL DEFAULT true,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.owners (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_key text NOT NULL UNIQUE,
    name text NOT NULL,
    owner_type text NOT NULL DEFAULT 'team' CHECK (owner_type IN ('team','department','vendor','customer')),
    contact_email text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.sites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    site_key text NOT NULL UNIQUE,
    name text NOT NULL,
    site_type text NOT NULL DEFAULT 'data_center' CHECK (site_type IN ('data_center','colocation','edge','cloud_region')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    address jsonb NOT NULL DEFAULT '{}'::jsonb,
    latitude numeric(9,6),
    longitude numeric(9,6),
    timezone text NOT NULL DEFAULT 'UTC',
    owner_id uuid REFERENCES inventory.owners(id),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    source_native_id text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    UNIQUE (source_id, source_native_id)
);

CREATE TABLE inventory.rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id uuid NOT NULL REFERENCES inventory.sites(id),
    room_key text NOT NULL,
    name text NOT NULL,
    floor text,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, room_key)
);

CREATE TABLE inventory.data_center_rows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL REFERENCES inventory.rooms(id),
    row_key text NOT NULL,
    name text NOT NULL,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (room_id, row_key)
);

CREATE TABLE inventory.racks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    row_id uuid NOT NULL REFERENCES inventory.data_center_rows(id),
    rack_key text NOT NULL,
    name text NOT NULL,
    rack_units smallint NOT NULL DEFAULT 42 CHECK (rack_units BETWEEN 1 AND 100),
    max_power_watts integer CHECK (max_power_watts > 0),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (row_id, rack_key)
);

CREATE TABLE inventory.servers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_key text NOT NULL UNIQUE,
    hostname text NOT NULL,
    rack_id uuid REFERENCES inventory.racks(id),
    rack_unit_start smallint,
    rack_unit_height smallint CHECK (rack_unit_height IS NULL OR rack_unit_height > 0),
    server_type text NOT NULL CHECK (server_type IN ('physical','blade','appliance','bare_metal','edge')),
    manufacturer text,
    model text,
    serial_number text,
    asset_tag text,
    architecture text,
    operating_system text,
    operating_system_version text,
    bios_version text,
    bmc_address inet,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','failed','retired','unknown')),
    owner_id uuid REFERENCES inventory.owners(id),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    source_native_id text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (serial_number),
    UNIQUE (source_id, source_native_id)
);

CREATE TABLE inventory.cpu_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
    socket_index smallint NOT NULL CHECK (socket_index >= 0),
    manufacturer text,
    model text NOT NULL,
    architecture text,
    physical_cores smallint NOT NULL CHECK (physical_cores > 0),
    logical_processors smallint NOT NULL CHECK (logical_processors >= physical_cores),
    base_frequency_mhz integer CHECK (base_frequency_mhz > 0),
    max_frequency_mhz integer CHECK (max_frequency_mhz > 0),
    l3_cache_bytes bigint CHECK (l3_cache_bytes >= 0),
    numa_node smallint CHECK (numa_node >= 0),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (server_id, socket_index)
);

CREATE TABLE inventory.memory_modules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
    slot text NOT NULL,
    manufacturer text,
    part_number text,
    serial_number text,
    memory_type text,
    capacity_bytes bigint NOT NULL CHECK (capacity_bytes > 0),
    speed_mts integer CHECK (speed_mts > 0),
    ecc boolean,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (server_id, slot)
);

CREATE TABLE inventory.gpu_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
    device_index smallint NOT NULL CHECK (device_index >= 0),
    manufacturer text,
    model text NOT NULL,
    serial_number text,
    pci_address text,
    vram_bytes bigint NOT NULL CHECK (vram_bytes > 0),
    driver_version text,
    firmware_version text,
    compute_capability text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (server_id, device_index),
    UNIQUE NULLS NOT DISTINCT (server_id, pci_address)
);

CREATE TABLE inventory.storage_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id uuid NOT NULL REFERENCES inventory.servers(id) ON DELETE CASCADE,
    device_name text NOT NULL,
    manufacturer text,
    model text,
    serial_number text,
    media_type text CHECK (media_type IN ('hdd','ssd','nvme','virtual','other')),
    interface_type text,
    capacity_bytes bigint NOT NULL CHECK (capacity_bytes > 0),
    firmware_version text,
    raid_group text,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','degraded','failed','retired','unknown')),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (server_id, device_name)
);

CREATE TABLE inventory.network_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_key text NOT NULL UNIQUE,
    hostname text NOT NULL,
    rack_id uuid REFERENCES inventory.racks(id),
    device_type text NOT NULL CHECK (device_type IN ('switch','router','firewall','load_balancer','wireless','other')),
    role text,
    manufacturer text,
    model text,
    serial_number text,
    operating_system text,
    operating_system_version text,
    management_address inet,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','failed','retired','unknown')),
    owner_id uuid REFERENCES inventory.owners(id),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    source_native_id text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (serial_number),
    UNIQUE (source_id, source_native_id)
);

CREATE TABLE inventory.network_interfaces (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id uuid REFERENCES inventory.servers(id) ON DELETE CASCADE,
    network_device_id uuid REFERENCES inventory.network_devices(id) ON DELETE CASCADE,
    interface_name text NOT NULL,
    interface_type text,
    mac_address macaddr,
    ip_addresses inet[] NOT NULL DEFAULT '{}',
    mtu integer CHECK (mtu > 0),
    speed_bps bigint CHECK (speed_bps > 0),
    administrative_status text CHECK (administrative_status IN ('up','down','unknown')),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(server_id, network_device_id) = 1)
);

CREATE UNIQUE INDEX network_interfaces_server_name_uq
    ON inventory.network_interfaces(server_id, interface_name) WHERE server_id IS NOT NULL;
CREATE UNIQUE INDEX network_interfaces_device_name_uq
    ON inventory.network_interfaces(network_device_id, interface_name) WHERE network_device_id IS NOT NULL;

CREATE TABLE inventory.network_segments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id uuid REFERENCES inventory.sites(id),
    segment_key text NOT NULL UNIQUE,
    name text NOT NULL,
    segment_type text NOT NULL CHECK (segment_type IN ('vlan','vrf','subnet','network')),
    vlan_id integer CHECK (vlan_id BETWEEN 1 AND 4094),
    cidr cidr,
    gateway inet,
    vrf_name text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.storage_systems (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    storage_key text NOT NULL UNIQUE,
    name text NOT NULL,
    site_id uuid REFERENCES inventory.sites(id),
    rack_id uuid REFERENCES inventory.racks(id),
    storage_type text NOT NULL CHECK (storage_type IN ('san','nas','object','hyperconverged','other')),
    manufacturer text,
    model text,
    serial_number text,
    raw_capacity_bytes bigint CHECK (raw_capacity_bytes > 0),
    usable_capacity_bytes bigint CHECK (usable_capacity_bytes > 0),
    management_address inet,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','degraded','failed','maintenance','retired','unknown')),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.hypervisors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hypervisor_key text NOT NULL UNIQUE,
    server_id uuid NOT NULL UNIQUE REFERENCES inventory.servers(id),
    hypervisor_type text NOT NULL,
    version text,
    cluster_name text,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','maintenance','disconnected','failed','retired','unknown')),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.virtual_machines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vm_key text NOT NULL UNIQUE,
    name text NOT NULL,
    hostname text,
    hypervisor_id uuid REFERENCES inventory.hypervisors(id),
    vcpu_count smallint NOT NULL CHECK (vcpu_count > 0),
    memory_bytes bigint NOT NULL CHECK (memory_bytes > 0),
    provisioned_storage_bytes bigint CHECK (provisioned_storage_bytes > 0),
    operating_system text,
    operating_system_version text,
    ip_addresses inet[] NOT NULL DEFAULT '{}',
    status text NOT NULL DEFAULT 'running' CHECK (status IN ('planned','running','stopped','suspended','failed','retired','unknown')),
    owner_id uuid REFERENCES inventory.owners(id),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    source_native_id text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_id, source_native_id)
);

CREATE TABLE inventory.k8s_clusters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cluster_key text NOT NULL UNIQUE,
    name text NOT NULL,
    site_id uuid REFERENCES inventory.sites(id),
    distribution text,
    version text,
    api_endpoint text,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','degraded','offline','maintenance','retired','unknown')),
    owner_id uuid REFERENCES inventory.owners(id),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    source_native_id text,
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_id, source_native_id)
);

CREATE TABLE inventory.k8s_nodes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cluster_id uuid NOT NULL REFERENCES inventory.k8s_clusters(id) ON DELETE CASCADE,
    node_uid text NOT NULL,
    name text NOT NULL,
    server_id uuid REFERENCES inventory.servers(id),
    vm_id uuid REFERENCES inventory.virtual_machines(id),
    role text NOT NULL DEFAULT 'worker' CHECK (role IN ('control_plane','worker','control_plane_worker')),
    architecture text,
    operating_system text,
    kernel_version text,
    kubelet_version text,
    cpu_capacity_millicores integer CHECK (cpu_capacity_millicores > 0),
    memory_capacity_bytes bigint CHECK (memory_capacity_bytes > 0),
    gpu_capacity integer NOT NULL DEFAULT 0 CHECK (gpu_capacity >= 0),
    status text NOT NULL DEFAULT 'ready' CHECK (status IN ('ready','not_ready','unknown','retired')),
    labels jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_simulated boolean NOT NULL DEFAULT false,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(server_id, vm_id) <= 1),
    UNIQUE (cluster_id, node_uid),
    UNIQUE (cluster_id, name)
);

CREATE TABLE inventory.k8s_namespaces (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cluster_id uuid NOT NULL REFERENCES inventory.k8s_clusters(id) ON DELETE CASCADE,
    namespace_uid text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','terminating','unknown')),
    labels jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_simulated boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cluster_id, namespace_uid),
    UNIQUE (cluster_id, name)
);

CREATE TABLE inventory.k8s_workloads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace_id uuid NOT NULL REFERENCES inventory.k8s_namespaces(id) ON DELETE CASCADE,
    workload_uid text NOT NULL,
    name text NOT NULL,
    workload_type text NOT NULL CHECK (workload_type IN ('Deployment','StatefulSet','DaemonSet','Job','CronJob','ReplicaSet')),
    desired_replicas integer CHECK (desired_replicas >= 0),
    available_replicas integer CHECK (available_replicas >= 0),
    container_images text[] NOT NULL DEFAULT '{}',
    labels jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_simulated boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (namespace_id, workload_uid)
);

CREATE TABLE inventory.k8s_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace_id uuid NOT NULL REFERENCES inventory.k8s_namespaces(id) ON DELETE CASCADE,
    service_uid text NOT NULL,
    name text NOT NULL,
    service_type text,
    cluster_ip inet,
    external_addresses inet[] NOT NULL DEFAULT '{}',
    ports jsonb NOT NULL DEFAULT '[]'::jsonb,
    selector jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_simulated boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (namespace_id, service_uid)
);

CREATE TABLE inventory.k8s_pods (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace_id uuid NOT NULL REFERENCES inventory.k8s_namespaces(id) ON DELETE CASCADE,
    node_id uuid REFERENCES inventory.k8s_nodes(id),
    workload_id uuid REFERENCES inventory.k8s_workloads(id),
    pod_uid text NOT NULL,
    name text NOT NULL,
    phase text NOT NULL CHECK (phase IN ('Pending','Running','Succeeded','Failed','Unknown')),
    pod_ip inet,
    qos_class text,
    restart_policy text,
    labels jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_simulated boolean NOT NULL DEFAULT false,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (namespace_id, pod_uid)
);

CREATE TABLE inventory.k8s_containers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pod_id uuid NOT NULL REFERENCES inventory.k8s_pods(id) ON DELETE CASCADE,
    container_key text NOT NULL,
    name text NOT NULL,
    image text NOT NULL,
    image_id text,
    runtime text,
    cpu_request_millicores integer CHECK (cpu_request_millicores >= 0),
    cpu_limit_millicores integer CHECK (cpu_limit_millicores >= 0),
    memory_request_bytes bigint CHECK (memory_request_bytes >= 0),
    memory_limit_bytes bigint CHECK (memory_limit_bytes >= 0),
    gpu_request integer NOT NULL DEFAULT 0 CHECK (gpu_request >= 0),
    status text NOT NULL DEFAULT 'running' CHECK (status IN ('waiting','running','terminated','unknown')),
    is_simulated boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (pod_id, container_key)
);

CREATE TABLE inventory.business_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    service_key text NOT NULL UNIQUE,
    name text NOT NULL,
    description text,
    criticality text NOT NULL DEFAULT 'medium' CHECK (criticality IN ('low','medium','high','critical')),
    service_tier text,
    owner_id uuid REFERENCES inventory.owners(id),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_key text NOT NULL UNIQUE,
    name text NOT NULL,
    description text,
    application_type text,
    version text,
    environment text NOT NULL DEFAULT 'production',
    criticality text NOT NULL DEFAULT 'medium' CHECK (criticality IN ('low','medium','high','critical')),
    owner_id uuid REFERENCES inventory.owners(id),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory.application_components (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES inventory.applications(id) ON DELETE CASCADE,
    component_key text NOT NULL,
    name text NOT NULL,
    component_type text NOT NULL CHECK (component_type IN ('web','api','worker','database','cache','queue','integration','other')),
    version text,
    runtime text,
    listen_endpoints jsonb NOT NULL DEFAULT '[]'::jsonb,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','maintenance','retired')),
    is_simulated boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (application_id, component_key)
);

CREATE TABLE inventory.inventory_changes (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    change_type text NOT NULL CHECK (change_type IN ('discovered','created','updated','moved','status_changed','retired','deleted')),
    source_id uuid REFERENCES inventory.discovery_sources(id),
    is_simulated boolean NOT NULL DEFAULT false,
    previous_values jsonb,
    current_values jsonb,
    correlation_id uuid,
    recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX servers_rack_idx ON inventory.servers(rack_id);
CREATE INDEX servers_status_idx ON inventory.servers(status);
CREATE INDEX servers_last_seen_idx ON inventory.servers(last_seen_at);
CREATE INDEX network_devices_rack_idx ON inventory.network_devices(rack_id);
CREATE INDEX virtual_machines_hypervisor_idx ON inventory.virtual_machines(hypervisor_id);
CREATE INDEX k8s_nodes_cluster_idx ON inventory.k8s_nodes(cluster_id);
CREATE INDEX k8s_pods_node_idx ON inventory.k8s_pods(node_id);
CREATE INDEX k8s_pods_workload_idx ON inventory.k8s_pods(workload_id);
CREATE INDEX k8s_containers_pod_idx ON inventory.k8s_containers(pod_id);
CREATE INDEX inventory_changes_entity_idx ON inventory.inventory_changes(entity_type, entity_id, occurred_at DESC);
CREATE INDEX inventory_changes_time_idx ON inventory.inventory_changes(occurred_at DESC);

DO $$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'discovery_sources','owners','sites','rooms','data_center_rows','racks','servers',
        'cpu_devices','memory_modules','gpu_devices','storage_devices','network_devices',
        'network_interfaces','network_segments','storage_systems','hypervisors','virtual_machines',
        'k8s_clusters','k8s_nodes','k8s_namespaces','k8s_workloads','k8s_services','k8s_pods',
        'k8s_containers','business_services','applications','application_components'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER set_updated_at BEFORE UPDATE ON inventory.%I '
            'FOR EACH ROW EXECUTE FUNCTION inventory.set_updated_at()', table_name
        );
    END LOOP;
END;
$$;

CREATE VIEW inventory.server_capacity AS
SELECT
    s.id,
    s.server_key,
    s.hostname,
    COALESCE(cpu.socket_count, 0) AS cpu_sockets,
    COALESCE(cpu.physical_cores, 0) AS physical_cores,
    COALESCE(cpu.logical_processors, 0) AS logical_processors,
    COALESCE(mem.ram_bytes, 0) AS ram_bytes,
    COALESCE(gpu.gpu_count, 0) AS gpu_count,
    COALESCE(gpu.vram_bytes, 0) AS vram_bytes,
    COALESCE(disk.storage_bytes, 0) AS local_storage_bytes
FROM inventory.servers s
LEFT JOIN (
    SELECT server_id, count(*) AS socket_count, sum(physical_cores) AS physical_cores,
           sum(logical_processors) AS logical_processors
    FROM inventory.cpu_devices GROUP BY server_id
) cpu ON cpu.server_id = s.id
LEFT JOIN (
    SELECT server_id, sum(capacity_bytes) AS ram_bytes
    FROM inventory.memory_modules GROUP BY server_id
) mem ON mem.server_id = s.id
LEFT JOIN (
    SELECT server_id, count(*) AS gpu_count, sum(vram_bytes) AS vram_bytes
    FROM inventory.gpu_devices GROUP BY server_id
) gpu ON gpu.server_id = s.id
LEFT JOIN (
    SELECT server_id, sum(capacity_bytes) AS storage_bytes
    FROM inventory.storage_devices GROUP BY server_id
) disk ON disk.server_id = s.id;

CREATE VIEW inventory.inventory_summary AS
SELECT 'sites' AS entity_type, count(*)::bigint AS entity_count FROM inventory.sites
UNION ALL SELECT 'racks', count(*) FROM inventory.racks
UNION ALL SELECT 'servers', count(*) FROM inventory.servers
UNION ALL SELECT 'network_devices', count(*) FROM inventory.network_devices
UNION ALL SELECT 'storage_systems', count(*) FROM inventory.storage_systems
UNION ALL SELECT 'virtual_machines', count(*) FROM inventory.virtual_machines
UNION ALL SELECT 'k8s_clusters', count(*) FROM inventory.k8s_clusters
UNION ALL SELECT 'k8s_nodes', count(*) FROM inventory.k8s_nodes
UNION ALL SELECT 'k8s_namespaces', count(*) FROM inventory.k8s_namespaces
UNION ALL SELECT 'k8s_workloads', count(*) FROM inventory.k8s_workloads
UNION ALL SELECT 'k8s_pods', count(*) FROM inventory.k8s_pods
UNION ALL SELECT 'k8s_containers', count(*) FROM inventory.k8s_containers
UNION ALL SELECT 'applications', count(*) FROM inventory.applications
UNION ALL SELECT 'business_services', count(*) FROM inventory.business_services;

COMMENT ON SCHEMA inventory IS
    'Current-state relational inventory. Time-series utilization belongs in telemetry; cross-domain dependency edges belong in the later topology model.';

COMMIT;
