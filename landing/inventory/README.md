# Customer inventory CSV landing zone

The files in `templates/` form one internally consistent dummy customer
inventory and document the initial CSV contracts. They are reference files and
must not be processed in place.

When the ingestion service is implemented, copy a completed file into
`incoming/` using a timestamped name. Write it with an `.uploading` suffix and
rename it to `.csv` only after the upload is complete.

Recommended load order:

1. `sites.csv`, `rooms.csv`, `rows.csv`, `racks.csv`
2. `servers.csv`, followed by server CPU, memory, GPU, storage, and interface files
3. `network_devices.csv`, `network_interfaces.csv`, `network_segments.csv`, and `storage_systems.csv`
4. `hypervisors.csv`, `virtual_machines.csv`
5. Kubernetes clusters, nodes, namespaces, workloads, services, pods, and containers
6. `owners.csv`, `business_services.csv`, `applications.csv`, and `application_components.csv`

All capacities use bytes and network speeds use bits per second. Customer CSV
records will be marked as live (`is_simulated=false`) by the ingestion service;
the dummy values here should only be used for development and validation.
