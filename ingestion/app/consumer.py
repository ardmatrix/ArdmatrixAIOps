from __future__ import annotations

import logging
import signal
from collections.abc import Callable
from typing import Any

import psycopg
from kafka import KafkaConsumer
from prometheus_client import Counter, Gauge, start_http_server
from psycopg.types.json import Jsonb

from .common import as_bool, as_float, as_int, blank_to_none, json_deserializer
from .config import DATABASE_URL, KAFKA_BOOTSTRAP_SERVERS, KAFKA_TOPIC, METRICS_PORT

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("inventory-consumer")

ROWS_PROCESSED = Counter("inventory_consumer_rows_processed_total", "Inventory rows stored", ["entity_type"])
ROWS_REJECTED = Counter("inventory_consumer_rows_rejected_total", "Inventory rows rejected", ["entity_type"])
CONSUMER_UP = Gauge("inventory_consumer_up", "Whether the inventory consumer is running")
STOP = False


def stop_service(*_: object) -> None:
    global STOP
    STOP = True


def source_id_sql() -> str:
    return "(SELECT id FROM inventory.discovery_sources WHERE source_key='customer-csv')"


def upsert_owner(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.owners (owner_key,name,owner_type,contact_email)
        VALUES (%s,%s,%s,%s)
        ON CONFLICT (owner_key) DO UPDATE SET name=EXCLUDED.name,
            owner_type=EXCLUDED.owner_type, contact_email=EXCLUDED.contact_email
        RETURNING id
        """,
        (row["owner_key"], row["name"], row["owner_type"], blank_to_none(row["contact_email"])),
    ).fetchone()[0])


def upsert_site(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        f"""
        INSERT INTO inventory.sites
            (site_key,name,site_type,status,address,latitude,longitude,timezone,owner_id,source_id,source_native_id,is_simulated,
             region,environment,health_status,facility_power_capacity_kw,facility_power_used_kw,cooling_capacity_kw,
             temperature_c,humidity_pct,pue,monitoring_coverage_pct,inventory_completeness_pct)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,
            (SELECT id FROM inventory.owners WHERE owner_key=%s),{source_id_sql()},%s,false,
            %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (site_key) DO UPDATE SET name=EXCLUDED.name, site_type=EXCLUDED.site_type,
            status=EXCLUDED.status, address=EXCLUDED.address, latitude=EXCLUDED.latitude,
            longitude=EXCLUDED.longitude, timezone=EXCLUDED.timezone,
            owner_id=EXCLUDED.owner_id, source_id=EXCLUDED.source_id,
            source_native_id=EXCLUDED.source_native_id,region=EXCLUDED.region,
            environment=EXCLUDED.environment,health_status=EXCLUDED.health_status,
            facility_power_capacity_kw=EXCLUDED.facility_power_capacity_kw,
            facility_power_used_kw=EXCLUDED.facility_power_used_kw,cooling_capacity_kw=EXCLUDED.cooling_capacity_kw,
            temperature_c=EXCLUDED.temperature_c,humidity_pct=EXCLUDED.humidity_pct,pue=EXCLUDED.pue,
            monitoring_coverage_pct=EXCLUDED.monitoring_coverage_pct,
            inventory_completeness_pct=EXCLUDED.inventory_completeness_pct,is_simulated=false,last_seen_at=now()
        RETURNING id
        """,
        (row["site_key"], row["name"], row["site_type"], row["status"],
         Jsonb({"city": row["city"], "country": row["country"]}),
         float(row["latitude"]), float(row["longitude"]), row["timezone"],
         row["owner_key"], row["source_native_id"],blank_to_none(row.get("region")),
         row.get("environment","production"),row.get("health_status","healthy"),
         as_float(row.get("facility_power_capacity_kw")),as_float(row.get("facility_power_used_kw")),
         as_float(row.get("cooling_capacity_kw")),as_float(row.get("temperature_c")),
         as_float(row.get("humidity_pct")),as_float(row.get("pue")),
         as_float(row.get("monitoring_coverage_pct")) or 100,
         as_float(row.get("inventory_completeness_pct")) or 100),
    ).fetchone()[0])


def upsert_room(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.rooms (site_id,room_key,name,floor,status,is_simulated)
        VALUES ((SELECT id FROM inventory.sites WHERE site_key=%s),%s,%s,%s,%s,false)
        ON CONFLICT (site_id,room_key) DO UPDATE SET name=EXCLUDED.name,
            floor=EXCLUDED.floor,status=EXCLUDED.status,is_simulated=false
        RETURNING id
        """,
        (row["site_key"], row["room_key"], row["name"], blank_to_none(row["floor"]), row["status"]),
    ).fetchone()[0])


def upsert_row(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.data_center_rows (room_id,row_key,name,is_simulated)
        VALUES ((SELECT rm.id FROM inventory.rooms rm JOIN inventory.sites s ON s.id=rm.site_id
                 WHERE s.site_key=%s AND rm.room_key=%s),%s,%s,false)
        ON CONFLICT (room_id,row_key) DO UPDATE SET name=EXCLUDED.name,is_simulated=false
        RETURNING id
        """,
        (row["site_key"], row["room_key"], row["row_key"], row["name"]),
    ).fetchone()[0])


def upsert_rack(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.racks
            (row_id,rack_key,name,rack_units,max_power_watts,status,is_simulated,health_status,
             used_rack_units,current_power_watts,temperature_c,humidity_pct,monitoring_status)
        VALUES ((SELECT dr.id FROM inventory.data_center_rows dr
                 JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
                 WHERE s.site_key=%s AND rm.room_key=%s AND dr.row_key=%s),%s,%s,%s,%s,%s,false,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (row_id,rack_key) DO UPDATE SET name=EXCLUDED.name,
            rack_units=EXCLUDED.rack_units,max_power_watts=EXCLUDED.max_power_watts,
            status=EXCLUDED.status,health_status=EXCLUDED.health_status,
            used_rack_units=EXCLUDED.used_rack_units,current_power_watts=EXCLUDED.current_power_watts,
            temperature_c=EXCLUDED.temperature_c,humidity_pct=EXCLUDED.humidity_pct,
            monitoring_status=EXCLUDED.monitoring_status,is_simulated=false
        RETURNING id
        """,
        (row["site_key"], row["room_key"], row["row_key"], row["rack_key"], row["name"],
         as_int(row["rack_units"]), as_int(row["max_power_watts"]), row["status"],
         row.get("health_status","healthy"),as_int(row.get("used_rack_units")) or 0,
         as_int(row.get("current_power_watts")) or 0,as_float(row.get("temperature_c")),
         as_float(row.get("humidity_pct")),row.get("monitoring_status","monitored")),
    ).fetchone()[0])


def rack_id_sql() -> str:
    return """(SELECT r.id FROM inventory.racks r
        JOIN inventory.data_center_rows dr ON dr.id=r.row_id
        JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
        WHERE s.site_key=%s AND r.rack_key=%s)"""


def upsert_server(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        f"""
        INSERT INTO inventory.servers
            (server_key,hostname,rack_id,rack_unit_start,rack_unit_height,server_type,manufacturer,
             model,serial_number,asset_tag,architecture,operating_system,operating_system_version,
             status,owner_id,source_id,source_native_id,is_simulated,health_status,environment,criticality,
             monitoring_status,warranty_expiry,end_of_support,business_service)
        VALUES (%s,%s,{rack_id_sql()},%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
            (SELECT id FROM inventory.owners WHERE owner_key=%s),{source_id_sql()},%s,false,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (server_key) DO UPDATE SET hostname=EXCLUDED.hostname,rack_id=EXCLUDED.rack_id,
            rack_unit_start=EXCLUDED.rack_unit_start,rack_unit_height=EXCLUDED.rack_unit_height,
            manufacturer=EXCLUDED.manufacturer,model=EXCLUDED.model,serial_number=EXCLUDED.serial_number,
            asset_tag=EXCLUDED.asset_tag,architecture=EXCLUDED.architecture,
            operating_system=EXCLUDED.operating_system,
            operating_system_version=EXCLUDED.operating_system_version,status=EXCLUDED.status,
            owner_id=EXCLUDED.owner_id,source_id=EXCLUDED.source_id,
            source_native_id=EXCLUDED.source_native_id,health_status=EXCLUDED.health_status,
            environment=EXCLUDED.environment,criticality=EXCLUDED.criticality,
            monitoring_status=EXCLUDED.monitoring_status,warranty_expiry=EXCLUDED.warranty_expiry,
            end_of_support=EXCLUDED.end_of_support,business_service=EXCLUDED.business_service,
            is_simulated=false,last_seen_at=now()
        RETURNING id
        """,
        (row["server_key"], row["hostname"], row["site_key"], row["rack_key"],
         as_int(row["rack_unit_start"]), as_int(row["rack_unit_height"]), row["server_type"],
         blank_to_none(row["manufacturer"]), blank_to_none(row["model"]), blank_to_none(row["serial_number"]),
         blank_to_none(row["asset_tag"]), blank_to_none(row["architecture"]),
         blank_to_none(row["operating_system"]), blank_to_none(row["operating_system_version"]), row["status"],
         row["owner_key"], row["source_native_id"],row.get("health_status","healthy"),
         row.get("environment","production"),row.get("criticality","medium"),
         row.get("monitoring_status","monitored"),blank_to_none(row.get("warranty_expiry")),
         blank_to_none(row.get("end_of_support")),blank_to_none(row.get("business_service"))),
    ).fetchone()[0])


def upsert_cpu(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.cpu_devices
            (server_id,socket_index,manufacturer,model,architecture,physical_cores,logical_processors,
             base_frequency_mhz,max_frequency_mhz,l3_cache_bytes,numa_node)
        VALUES ((SELECT id FROM inventory.servers WHERE server_key=%s),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (server_id,socket_index) DO UPDATE SET manufacturer=EXCLUDED.manufacturer,
            model=EXCLUDED.model,architecture=EXCLUDED.architecture,
            physical_cores=EXCLUDED.physical_cores,logical_processors=EXCLUDED.logical_processors,
            base_frequency_mhz=EXCLUDED.base_frequency_mhz,max_frequency_mhz=EXCLUDED.max_frequency_mhz,
            l3_cache_bytes=EXCLUDED.l3_cache_bytes,numa_node=EXCLUDED.numa_node
        RETURNING id
        """,
        (row["server_key"], as_int(row["socket_index"]), row["manufacturer"], row["model"], row["architecture"],
         as_int(row["physical_cores"]), as_int(row["logical_processors"]), as_int(row["base_frequency_mhz"]),
         as_int(row["max_frequency_mhz"]), as_int(row["l3_cache_bytes"]), as_int(row["numa_node"])),
    ).fetchone()[0])


def upsert_memory(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.memory_modules
            (server_id,slot,manufacturer,part_number,serial_number,memory_type,capacity_bytes,speed_mts,ecc)
        VALUES ((SELECT id FROM inventory.servers WHERE server_key=%s),%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (server_id,slot) DO UPDATE SET manufacturer=EXCLUDED.manufacturer,
            part_number=EXCLUDED.part_number,serial_number=EXCLUDED.serial_number,
            memory_type=EXCLUDED.memory_type,capacity_bytes=EXCLUDED.capacity_bytes,
            speed_mts=EXCLUDED.speed_mts,ecc=EXCLUDED.ecc
        RETURNING id
        """,
        (row["server_key"], row["slot"], row["manufacturer"], blank_to_none(row["part_number"]),
         blank_to_none(row["serial_number"]), row["memory_type"], as_int(row["capacity_bytes"]),
         as_int(row["speed_mts"]), as_bool(row["ecc"])),
    ).fetchone()[0])


def upsert_gpu(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.gpu_devices
            (server_id,device_index,manufacturer,model,serial_number,pci_address,vram_bytes,
             driver_version,firmware_version,compute_capability)
        VALUES ((SELECT id FROM inventory.servers WHERE server_key=%s),%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (server_id,device_index) DO UPDATE SET manufacturer=EXCLUDED.manufacturer,
            model=EXCLUDED.model,serial_number=EXCLUDED.serial_number,pci_address=EXCLUDED.pci_address,
            vram_bytes=EXCLUDED.vram_bytes,driver_version=EXCLUDED.driver_version,
            firmware_version=EXCLUDED.firmware_version,compute_capability=EXCLUDED.compute_capability
        RETURNING id
        """,
        (row["server_key"], as_int(row["device_index"]), row["manufacturer"], row["model"],
         blank_to_none(row["serial_number"]), blank_to_none(row["pci_address"]), as_int(row["vram_bytes"]),
         blank_to_none(row["driver_version"]), blank_to_none(row["firmware_version"]),
         blank_to_none(row["compute_capability"])),
    ).fetchone()[0])


def upsert_storage(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        """
        INSERT INTO inventory.storage_devices
            (server_id,device_name,manufacturer,model,serial_number,media_type,interface_type,
             capacity_bytes,firmware_version,raid_group,status)
        VALUES ((SELECT id FROM inventory.servers WHERE server_key=%s),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (server_id,device_name) DO UPDATE SET manufacturer=EXCLUDED.manufacturer,
            model=EXCLUDED.model,serial_number=EXCLUDED.serial_number,media_type=EXCLUDED.media_type,
            interface_type=EXCLUDED.interface_type,capacity_bytes=EXCLUDED.capacity_bytes,
            firmware_version=EXCLUDED.firmware_version,raid_group=EXCLUDED.raid_group,status=EXCLUDED.status
        RETURNING id
        """,
        (row["server_key"], row["device_name"], row["manufacturer"], row["model"],
         blank_to_none(row["serial_number"]), row["media_type"], row["interface_type"],
         as_int(row["capacity_bytes"]), blank_to_none(row["firmware_version"]),
         blank_to_none(row["raid_group"]), row["status"]),
    ).fetchone()[0])


def upsert_network_device(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        f"""
        INSERT INTO inventory.network_devices
            (device_key,hostname,rack_id,device_type,role,manufacturer,model,serial_number,
             operating_system,operating_system_version,management_address,status,owner_id,
             source_id,source_native_id,is_simulated)
        VALUES (%s,%s,{rack_id_sql()},%s,%s,%s,%s,%s,%s,%s,%s,%s,
            (SELECT id FROM inventory.owners WHERE owner_key=%s),{source_id_sql()},%s,false)
        ON CONFLICT (device_key) DO UPDATE SET hostname=EXCLUDED.hostname,rack_id=EXCLUDED.rack_id,
            device_type=EXCLUDED.device_type,role=EXCLUDED.role,manufacturer=EXCLUDED.manufacturer,
            model=EXCLUDED.model,serial_number=EXCLUDED.serial_number,
            operating_system=EXCLUDED.operating_system,
            operating_system_version=EXCLUDED.operating_system_version,
            management_address=EXCLUDED.management_address,status=EXCLUDED.status,
            owner_id=EXCLUDED.owner_id,source_id=EXCLUDED.source_id,
            source_native_id=EXCLUDED.source_native_id,is_simulated=false,last_seen_at=now()
        RETURNING id
        """,
        (row["device_key"], row["hostname"], row["site_key"], row["rack_key"], row["device_type"],
         row["role"], row["manufacturer"], row["model"], row["serial_number"], row["operating_system"],
         row["operating_system_version"], row["management_address"], row["status"], row["owner_key"],
         row["source_native_id"]),
    ).fetchone()[0])


def upsert_interface(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    parent_type = row["parent_type"]
    if parent_type not in {"server", "network_device"}:
        raise ValueError("parent_type must be server or network_device")
    server_key = row["parent_key"] if parent_type == "server" else None
    device_key = row["parent_key"] if parent_type == "network_device" else None
    if parent_type == "server":
        existing = connection.execute(
            """
            SELECT ni.id FROM inventory.network_interfaces ni
            JOIN inventory.servers s ON s.id=ni.server_id
            WHERE s.server_key=%s AND ni.interface_name=%s
            """, (server_key, row["interface_name"])
        ).fetchone()
    else:
        existing = connection.execute(
            """
            SELECT ni.id FROM inventory.network_interfaces ni
            JOIN inventory.network_devices nd ON nd.id=ni.network_device_id
            WHERE nd.device_key=%s AND ni.interface_name=%s
            """, (device_key, row["interface_name"])
        ).fetchone()
    addresses = [value.strip() for value in row["ip_addresses"].split(";") if value.strip()]
    values = (row["interface_type"], blank_to_none(row["mac_address"]), addresses,
              as_int(row["mtu"]), as_int(row["speed_bps"]), row["administrative_status"])
    if existing:
        return str(connection.execute(
            """UPDATE inventory.network_interfaces SET interface_type=%s,mac_address=%s,
            ip_addresses=%s,mtu=%s,speed_bps=%s,administrative_status=%s WHERE id=%s RETURNING id""",
            (*values, existing[0]),
        ).fetchone()[0])
    return str(connection.execute(
        """
        INSERT INTO inventory.network_interfaces
            (server_id,network_device_id,interface_name,interface_type,mac_address,ip_addresses,
             mtu,speed_bps,administrative_status)
        VALUES ((SELECT id FROM inventory.servers WHERE server_key=%s),
                (SELECT id FROM inventory.network_devices WHERE device_key=%s),%s,%s,%s,%s,%s,%s,%s)
        RETURNING id
        """, (server_key, device_key, row["interface_name"], *values)
    ).fetchone()[0])


def upsert_hypervisor(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    return str(connection.execute(
        f"""
        INSERT INTO inventory.hypervisors
            (hypervisor_key,server_id,hypervisor_type,version,cluster_name,status,source_id,is_simulated)
        VALUES (%s,(SELECT id FROM inventory.servers WHERE server_key=%s),%s,%s,%s,%s,
                {source_id_sql()},false)
        ON CONFLICT (hypervisor_key) DO UPDATE SET server_id=EXCLUDED.server_id,
            hypervisor_type=EXCLUDED.hypervisor_type,version=EXCLUDED.version,
            cluster_name=EXCLUDED.cluster_name,status=EXCLUDED.status,
            source_id=EXCLUDED.source_id,is_simulated=false
        RETURNING id
        """,
        (row["hypervisor_key"], row["server_key"], row["hypervisor_type"],
         blank_to_none(row["version"]), blank_to_none(row["cluster_name"]), row["status"]),
    ).fetchone()[0])


def upsert_virtual_machine(connection: psycopg.Connection[Any], row: dict[str, str]) -> str:
    addresses = [value.strip() for value in row["ip_addresses"].split(";") if value.strip()]
    return str(connection.execute(
        f"""
        INSERT INTO inventory.virtual_machines
            (vm_key,name,hostname,hypervisor_id,vcpu_count,memory_bytes,
             provisioned_storage_bytes,operating_system,operating_system_version,
             ip_addresses,status,owner_id,source_id,source_native_id,is_simulated,health_status,environment,
             criticality,monitoring_status,cpu_utilization_pct,memory_utilization_pct,storage_utilization_pct,
             uptime_pct,snapshot_count,backup_status)
        VALUES (%s,%s,%s,
            (SELECT id FROM inventory.hypervisors WHERE hypervisor_key=%s),
            %s,%s,%s,%s,%s,%s,%s,
            (SELECT id FROM inventory.owners WHERE owner_key=%s),
            {source_id_sql()},%s,false,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (vm_key) DO UPDATE SET name=EXCLUDED.name,hostname=EXCLUDED.hostname,
            hypervisor_id=EXCLUDED.hypervisor_id,vcpu_count=EXCLUDED.vcpu_count,
            memory_bytes=EXCLUDED.memory_bytes,
            provisioned_storage_bytes=EXCLUDED.provisioned_storage_bytes,
            operating_system=EXCLUDED.operating_system,
            operating_system_version=EXCLUDED.operating_system_version,
            ip_addresses=EXCLUDED.ip_addresses,status=EXCLUDED.status,
            owner_id=EXCLUDED.owner_id,source_id=EXCLUDED.source_id,
            source_native_id=EXCLUDED.source_native_id,health_status=EXCLUDED.health_status,
            environment=EXCLUDED.environment,criticality=EXCLUDED.criticality,
            monitoring_status=EXCLUDED.monitoring_status,cpu_utilization_pct=EXCLUDED.cpu_utilization_pct,
            memory_utilization_pct=EXCLUDED.memory_utilization_pct,
            storage_utilization_pct=EXCLUDED.storage_utilization_pct,uptime_pct=EXCLUDED.uptime_pct,
            snapshot_count=EXCLUDED.snapshot_count,backup_status=EXCLUDED.backup_status,
            is_simulated=false,last_seen_at=now()
        RETURNING id
        """,
        (row["vm_key"], row["name"], blank_to_none(row["hostname"]), row["hypervisor_key"],
         as_int(row["vcpu_count"]), as_int(row["memory_bytes"]),
         as_int(row["provisioned_storage_bytes"]), blank_to_none(row["operating_system"]),
         blank_to_none(row["operating_system_version"]), addresses, row["status"],
         row["owner_key"], row["source_native_id"],row.get("health_status","healthy"),
         row.get("environment","production"),row.get("criticality","medium"),
         row.get("monitoring_status","monitored"),as_float(row.get("cpu_utilization_pct")) or 0,
         as_float(row.get("memory_utilization_pct")) or 0,as_float(row.get("storage_utilization_pct")) or 0,
         as_float(row.get("uptime_pct")) or 100,as_int(row.get("snapshot_count")) or 0,
         row.get("backup_status","protected")),
    ).fetchone()[0])


HANDLERS: dict[str, Callable[[psycopg.Connection[Any], dict[str, str]], str]] = {
    "owners": upsert_owner,
    "sites": upsert_site,
    "rooms": upsert_room,
    "rows": upsert_row,
    "racks": upsert_rack,
    "servers": upsert_server,
    "server_cpus": upsert_cpu,
    "server_memory": upsert_memory,
    "server_gpus": upsert_gpu,
    "server_storage": upsert_storage,
    "network_devices": upsert_network_device,
    "network_interfaces": upsert_interface,
    "hypervisors": upsert_hypervisor,
    "virtual_machines": upsert_virtual_machine,
}


def ensure_source(connection: psycopg.Connection[Any]) -> None:
    connection.execute(
        """
        INSERT INTO inventory.discovery_sources
            (source_key,name,source_type,is_simulated,enabled)
        VALUES ('customer-csv','Customer CSV Landing Zone','file',false,true)
        ON CONFLICT (source_key) DO UPDATE SET enabled=true
        """
    )
    connection.commit()


def update_completion(connection: psycopg.Connection[Any], run_id: str) -> None:
    connection.execute(
        """
        UPDATE ingestion.file_runs
        SET status = CASE WHEN rows_processed + rows_rejected >= rows_published THEN
                CASE WHEN rows_rejected > 0 THEN 'rejected' ELSE 'completed' END
            ELSE status END,
            completed_at = CASE WHEN rows_processed + rows_rejected >= rows_published THEN now() ELSE completed_at END
        WHERE id=%s
        """, (run_id,)
    )


def process_message(connection: psycopg.Connection[Any], payload: dict[str, Any]) -> None:
    message_id = payload["message_id"]
    run_id = payload["file_run_id"]
    entity_type = payload["entity_type"]
    if connection.execute(
        "SELECT 1 FROM ingestion.processed_messages WHERE message_id=%s", (message_id,)
    ).fetchone():
        connection.commit()
        return
    handler = HANDLERS.get(entity_type)
    if handler is None:
        raise ValueError(f"unsupported entity type: {entity_type}")
    entity_id = handler(connection, payload["data"])
    connection.execute(
        """
        INSERT INTO ingestion.processed_messages (message_id,file_run_id,entity_type,entity_id)
        VALUES (%s,%s,%s,%s)
        """, (message_id, run_id, entity_type, entity_id)
    )
    connection.execute(
        "UPDATE ingestion.file_runs SET rows_processed=rows_processed+1 WHERE id=%s", (run_id,)
    )
    update_completion(connection, run_id)
    connection.commit()
    ROWS_PROCESSED.labels(entity_type=entity_type).inc()


def reject_message(connection: psycopg.Connection[Any], payload: dict[str, Any], exc: Exception) -> None:
    connection.rollback()
    run_id = payload["file_run_id"]
    entity_type = payload["entity_type"]
    connection.execute(
        """
        INSERT INTO ingestion.row_errors
            (file_run_id,row_number,error_code,error_message,row_data)
        VALUES (%s,%s,'DATABASE_REJECTED',%s,%s)
        """, (run_id, payload.get("row_number"), str(exc), Jsonb(payload.get("data")))
    )
    connection.execute(
        "UPDATE ingestion.file_runs SET rows_rejected=rows_rejected+1,error_summary=%s WHERE id=%s",
        (str(exc), run_id),
    )
    update_completion(connection, run_id)
    connection.commit()
    ROWS_REJECTED.labels(entity_type=entity_type).inc()
    LOG.exception("rejected %s row %s", entity_type, payload.get("row_number"))


def main() -> None:
    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    start_http_server(METRICS_PORT)
    connection = psycopg.connect(DATABASE_URL)
    ensure_source(connection)
    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id="inventory-postgres-v1",
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        value_deserializer=json_deserializer,
    )
    CONSUMER_UP.set(1)
    LOG.info("consuming %s", KAFKA_TOPIC)
    try:
        while not STOP:
            batches = consumer.poll(timeout_ms=1000, max_records=100)
            for messages in batches.values():
                for message in messages:
                    try:
                        process_message(connection, message.value)
                    except Exception as exc:
                        reject_message(connection, message.value, exc)
                    consumer.commit()
    finally:
        CONSUMER_UP.set(0)
        consumer.close()
        connection.close()


if __name__ == "__main__":
    main()
