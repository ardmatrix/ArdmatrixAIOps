from __future__ import annotations

import json
import os
import re
from contextlib import contextmanager
from typing import Any, Literal

import psycopg
from psycopg import sql
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from openai import OpenAI
from pydantic import BaseModel, Field


DATABASE_URL = os.environ["DATABASE_URL"]
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "openai").casefold()
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
LLM_API_KEY = os.getenv("OPENAI_API_KEY") or os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-5.4-mini")
LLM_REASONING_EFFORT = os.getenv("LLM_REASONING_EFFORT", "none")
MAX_ROWS = int(os.getenv("INVENTORY_ASSISTANT_MAX_ROWS", "50"))
MAX_COMPLETION_TOKENS = int(os.getenv("INVENTORY_ASSISTANT_MAX_COMPLETION_TOKENS", "256"))

app = FastAPI(title="ARDMATRIX AIOps Expert", version="1.0.0")
app.mount("/static", StaticFiles(directory="/app/app/static"), name="static")


@app.get("/", include_in_schema=False)
def chat_page() -> FileResponse:
    return FileResponse("/app/app/static/index.html")


class ChatRequest(BaseModel):
    message: str = Field(min_length=2, max_length=2000)
    history: list[dict[str, str]] = Field(default_factory=list, max_length=20)


class ChatResponse(BaseModel):
    answer: str
    tools_used: list[str]
    model: str


def fast_inventory_answer(question: str) -> ChatResponse | None:
    """Answer common operational questions without an expensive LLM round trip."""
    text = question.casefold()
    wants_server_connectivity = "server" in text and any(term in text for term in (
        "connectivity", "connected", "switch port", "network path", "network device", "which switch"
    ))
    if wants_server_connectivity:
        match = re.search(r"\b(?:tech-)?srv-[a-z0-9-]+\b", text)
        if not match:
            return ChatResponse(
                answer=("Yes. Provide a server key, for example `srv-bengaluru-01-01`. I can return its server NIC, "
                        "MAC/IP, exact access switch and port, VLAN/VRF/subnet, redundant core switches, firewall, "
                        "WAN router, link status, and last verification time."),
                tools_used=["inventory_query:server_connectivity:fast"], model="database-fast-path"
            )
        server_key = match.group(0)
        result = inventory_query("server_connectivity", server_key=server_key)
        if not result["rows"]:
            return ChatResponse(
                answer=f"No physical network attachment was found for server `{server_key}`. Check the server key and try again.",
                tools_used=["inventory_query:server_connectivity:fast"], model="database-fast-path"
            )
        row = result["rows"][0]
        answer = (
            f"Server connectivity for `{row['server_key']}`:\n"
            f"• Server NIC: {row['server_interface']} · MAC {row['mac_address']} · IP {row['server_ip_addresses']}\n"
            f"• Access attachment: {row['switch_name']} · port {row['switch_interface']} · "
            f"{row['switch_vendor']} {row['switch_model']}\n"
            f"• Network: VLAN {row['vlan_id']} ({row['vlan_name']}) · VRF {row['vrf_name']} · "
            f"subnet {row['cidr']} · gateway {row['gateway']}\n"
            f"• Upstream: {row['upstream_core_01']} / {row['upstream_core_02']} → "
            f"{row['upstream_firewall']} → {row['upstream_router']}\n"
            f"• Link status: {row['connection_status']} · last verified {row['last_seen_at']}\n"
            "This connectivity record is simulated for the demo."
        )
        return ChatResponse(answer=answer, tools_used=["inventory_query:server_connectivity:fast"], model="database-fast-path")
    count_question = any(term in text for term in ("how many", "count", "number of"))
    wants_unhealthy_pods = count_question and "pod" in text and not any(
        term in text for term in (" by ", "list", "show", "which", "where")
    ) and any(
        term in text for term in ("unhealthy", "not healthy", "not running", "failed", "pending")
    )
    if wants_unhealthy_pods:
        result = inventory_query("pod_health")
        phase_counts = {row["phase"]: row["pod_count"] for row in result["rows"]}
        unhealthy = sum(
            count for phase, count in phase_counts.items() if phase not in ("Running", "Succeeded")
        )
        details = ", ".join(
            f"{phase}: {count}" for phase, count in phase_counts.items()
            if phase not in ("Running", "Succeeded")
        ) or "no unhealthy phases"
        total = sum(phase_counts.values())
        return ChatResponse(
            answer=(f"There are {unhealthy:,} unhealthy pods out of {total:,} total pods. "
                    f"Unhealthy means a phase other than Running or Succeeded ({details})."),
            tools_used=["inventory_query:pod_health:fast"], model="database-fast-path"
        )
    wants_server_models = "server" in text and (
        "unique model" in text or "server models" in text or "models of server" in text
        or "models are" in text or "model names" in text
    )
    if wants_server_models:
        result = inventory_query("server_models")
        model_rows = result["rows"]
        wants_model_counts = any(term in text for term in ("how many", "count", "quantity", "number of"))
        if wants_model_counts:
            models = "\n".join(
                f"• {row['manufacturer']} {row['model']}: {row['server_count']:,} "
                f"{'server' if row['server_count'] == 1 else 'servers'}" for row in model_rows
            )
        else:
            models = "\n".join(f"• {row['manufacturer']} {row['model']}" for row in model_rows)
        return ChatResponse(
            answer=f"Unique server models ({len(model_rows)}):\n{models}",
            tools_used=["inventory_query:server_models:fast"], model="database-fast-path"
        )
    wants_server_vendors = "server" in text and any(term in text for term in ("vendor", "manufacturer", "make"))
    if wants_server_vendors:
        result = inventory_query("server_vendors")
        vendor_rows = result["rows"]
        server_count = sum(row["server_count"] for row in vendor_rows)
        vendors = "\n".join(
            f"• {row['manufacturer']}: {row['server_count']:,} "
            f"{'server' if row['server_count'] == 1 else 'servers'}" for row in vendor_rows
        )
        return ChatResponse(
            answer=f"There are {server_count:,} physical servers from {len(vendor_rows)} vendors/manufacturers:\n{vendors}",
            tools_used=["inventory_query:server_vendors:fast"], model="database-fast-path"
        )

    entity_terms = [
        ("Data centers", "data_centers", ("data center", "datacenter", "sites")),
        ("Racks", "racks", ("rack",)),
        ("Physical servers", "servers", ("server", "physical host")),
        ("Virtual machines", "virtual_machines", ("virtual machine", "vms", "vm ")),
        ("Kubernetes clusters", "kubernetes_clusters", ("kubernetes cluster", "k8s cluster")),
        ("Kubernetes pods", "kubernetes_pods", ("pod",)),
        ("Applications", "applications", ("application",)),
        ("Business services", "business_services", ("business service",)),
        ("Open alerts", "open_alerts", ("alert",)),
    ]
    requested_entities = [(label, key) for label, key, terms in entity_terms if any(term in text for term in terms)]
    qualified_count = any(term in text for term in (
        "critical", "warning", "healthy", "unhealthy", "pending", "running", "vendor", "manufacturer",
        "model", "operating system", "owner", "environment", " in ", " at ", " by ", " per ", " with ", "without"
    ))
    if count_question and requested_entities and not qualified_count:
        result = inventory_query("summary")
        counts = {row["entity_type"]: row["entity_count"] for row in result["rows"]}
        answer = "\n".join(f"• {label}: {counts.get(key, 0):,}" for label, key in requested_entities)
        return ChatResponse(answer=answer, tools_used=["inventory_query:summary:fast"], model="database-fast-path")

    if not any(term in text for term in ("summary", "total inventory", "inventory overview", "complete inventory")):
        return None
    operation = "summary"
    result = inventory_query(operation)
    data = result["rows"]
    simulated = any(bool(row.get("is_simulated")) for row in data)
    note = " Data includes simulated telemetry." if simulated else ""
    if operation == "summary":
        counts = {row["entity_type"]: row["entity_count"] for row in data}
        ordered = [
            ("Data centers", "data_centers"), ("Racks", "racks"), ("Physical servers", "servers"),
            ("Virtual machines", "virtual_machines"), ("Kubernetes clusters", "kubernetes_clusters"),
            ("Kubernetes pods", "kubernetes_pods"), ("Applications", "applications"),
            ("Business services", "business_services"), ("Open alerts", "open_alerts"),
        ]
        answer = "Inventory overview:\n" + "\n".join(f"• {label}: {counts.get(key, 0):,}" for label, key in ordered)
    elif operation == "alerts":
        critical = sum(row.get("severity") == "critical" for row in data)
        warning = sum(row.get("severity") == "warning" for row in data)
        items = "\n".join(f"• [{row['severity'].upper()}] {row['title']} ({row['entity_type']})" for row in data[:10])
        answer = f"Open alerts: {len(data)} returned — {critical} critical and {warning} warning.\n{items}"
    elif operation == "sites":
        items = "\n".join(f"• {r['site_key']} — {r['name']}: {r['health_status']}, {r['server_count']} servers, {r['vm_count']} VMs, {r['open_alerts']} alerts" for r in data[:10])
        answer = f"Data centers ({len(data)}):\n{items}"
    elif operation == "racks":
        items = "\n".join(f"• {r['rack_key']} ({r['site_key']}): {r['health_status']}, {r['server_count']} servers, {r['open_alerts']} alerts" for r in data[:10])
        answer = f"Racks: {len(data)} rows returned. Showing the first {min(10, len(data))}:\n{items}"
    elif operation == "servers":
        items = "\n".join(f"• {r['server_key']} — {r['hostname']}: {r['health_status']}, CPU {r['cpu_utilization_percent']}%, memory {r['memory_utilization_percent']}%, {r['open_alerts']} alerts" for r in data[:10])
        answer = f"Servers: {len(data)} rows returned. Showing the first {min(10, len(data))}:\n{items}"
    elif operation == "virtual_machines":
        items = "\n".join(f"• {r['vm_key']} — {r['name']}: {r['health_status']}, host {r['physical_host']}, CPU {r['cpu_utilization_pct']}%" for r in data[:10])
        answer = f"Virtual machines: {len(data)} rows returned. Showing the first {min(10, len(data))}:\n{items}"
    elif operation == "kubernetes":
        clusters = {r["cluster_name"] for r in data}
        pods = {r["pod"] for r in data if r.get("pod")}
        unhealthy = {r["pod"] for r in data if r.get("pod") and r.get("phase") not in ("Running", "Succeeded")}
        answer = f"Kubernetes inventory: {len(clusters)} clusters and {len(pods)} pods in the returned data; {len(unhealthy)} pods are not Running/Succeeded."
    else:
        apps = {r["application_key"]: r for r in data}
        critical = [r for r in apps.values() if r.get("criticality") == "critical"]
        items = "\n".join(f"• {r['application']} ({r['application_key']}): {r['status']}, {r['criticality']} criticality, service {r.get('business_service') or 'unassigned'}" for r in critical[:10])
        answer = f"Applications: {len(apps)} unique applications; {len(critical)} are critical.\n{items}"
    if result["row_count"] == result["max_rows"]:
        note += " The result reached the configured row limit and may be truncated."
    return ChatResponse(answer=answer + note, tools_used=[f"inventory_query:{operation}:fast"], model="database-fast-path")


@contextmanager
def database() -> Any:
    with psycopg.connect(DATABASE_URL, autocommit=True) as connection:
        connection.execute("SET default_transaction_read_only = on")
        connection.execute("SET statement_timeout = '5s'")
        yield connection


def rows(connection: Any, query: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with connection.cursor(row_factory=psycopg.rows.dict_row) as cursor:
        cursor.execute(query, params)
        return [dict(row) for row in cursor.fetchmany(MAX_ROWS)]


def inventory_query(
    operation: Literal[
        "summary", "sites", "racks", "servers", "virtual_machines",
        "kubernetes", "applications", "alerts", "search", "server_vendors", "server_models", "pod_health",
        "server_connectivity", "connectivity_paths"
    ],
    site_key: str | None = None,
    rack_key: str | None = None,
    server_key: str | None = None,
    search_term: str | None = None,
) -> dict[str, Any]:
    filters = (site_key, site_key)
    with database() as connection:
        if operation == "summary":
            result = rows(connection, """
                SELECT * FROM (
                  SELECT 'data_centers' entity_type,count(*)::bigint entity_count FROM inventory.sites
                  UNION ALL SELECT 'racks',count(*) FROM inventory.racks
                  UNION ALL SELECT 'servers',count(*) FROM inventory.servers
                  UNION ALL SELECT 'virtual_machines',count(*) FROM inventory.virtual_machines
                  UNION ALL SELECT 'kubernetes_clusters',count(*) FROM inventory.k8s_clusters
                  UNION ALL SELECT 'kubernetes_pods',count(*) FROM inventory.k8s_pods
                  UNION ALL SELECT 'applications',count(*) FROM inventory.applications
                  UNION ALL SELECT 'business_services',count(*) FROM inventory.business_services
                  UNION ALL SELECT 'open_alerts',count(*) FROM events.inventory_alerts WHERE status<>'resolved'
                ) summary ORDER BY entity_type
            """)
        elif operation == "sites":
            result = rows(connection, """
                SELECT site_key,name,region,environment,health_status,rack_count,server_count,vm_count,
                       open_alerts,critical_alerts,unmonitored_assets,facility_power_used_kw,
                       facility_power_capacity_kw,temperature_c,humidity_pct,pue,
                       monitoring_coverage_pct,owner,last_seen_at,is_simulated
                FROM inventory.data_center_operational_overview
                WHERE (%s::text IS NULL OR site_key=%s)
                ORDER BY CASE health_status WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,name
            """, filters)
        elif operation == "racks":
            result = rows(connection, """
                SELECT site_key,site_name,rack_key,name,room_name,row_name,health_status,rack_units,
                       used_rack_units,max_power_watts,current_power_watts,temperature_c,humidity_pct,
                       monitoring_status,server_count,vm_count,open_alerts,updated_at,is_simulated
                FROM inventory.rack_operational_overview
                WHERE (%s::text IS NULL OR site_key=%s) AND (%s::text IS NULL OR rack_key=%s)
                ORDER BY CASE health_status WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,site_name,name
            """, (site_key, site_key, rack_key, rack_key))
        elif operation == "servers":
            result = rows(connection, """
                SELECT site_key,site_name,rack_key,rack_name,server_key,hostname,health_status,status,
                       environment,criticality,monitoring_status,manufacturer,model,operating_system,
                       physical_cores,logical_processors,ram_bytes,local_storage_bytes,gpu_count,
                       cpu_utilization_percent,memory_utilization_percent,disk_utilization_percent,
                       temperature_celsius,power_consumption_watts,uptime_percent,available,vm_count,
                       open_alerts,owner,business_service,warranty_expiry,end_of_support,last_seen_at,is_simulated
                FROM inventory.server_operational_overview
                WHERE (%s::text IS NULL OR site_key=%s) AND (%s::text IS NULL OR rack_key=%s)
                  AND (%s::text IS NULL OR server_key=%s)
                ORDER BY CASE health_status WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,hostname
            """, (site_key, site_key, rack_key, rack_key, server_key, server_key))
        elif operation == "server_vendors":
            result = rows(connection, """
                SELECT COALESCE(NULLIF(trim(manufacturer), ''), 'Unknown') manufacturer,
                       count(*)::bigint server_count
                FROM inventory.servers
                GROUP BY COALESCE(NULLIF(trim(manufacturer), ''), 'Unknown')
                ORDER BY server_count DESC,manufacturer
            """)
        elif operation == "server_models":
            result = rows(connection, """
                SELECT COALESCE(NULLIF(trim(manufacturer), ''), 'Unknown') manufacturer,
                       COALESCE(NULLIF(trim(model), ''), 'Unknown') model,
                       count(*)::bigint server_count
                FROM inventory.servers
                GROUP BY COALESCE(NULLIF(trim(manufacturer), ''), 'Unknown'),
                         COALESCE(NULLIF(trim(model), ''), 'Unknown')
                ORDER BY manufacturer,model
            """)
        elif operation == "pod_health":
            result = rows(connection, """
                SELECT COALESCE(NULLIF(trim(phase), ''), 'Unknown') phase,
                       count(*)::bigint pod_count
                FROM inventory.k8s_pods
                GROUP BY COALESCE(NULLIF(trim(phase), ''), 'Unknown')
                ORDER BY phase
            """)
        elif operation == "virtual_machines":
            result = rows(connection, """
                SELECT site_key,site_name,rack_key,rack_name,server_key,physical_host,vm_key,name,hostname,
                       health_status,status,environment,criticality,monitoring_status,vcpu_count,memory_bytes,
                       provisioned_storage_bytes,cpu_utilization_pct,memory_utilization_pct,
                       storage_utilization_pct,uptime_pct,snapshot_count,backup_status,operating_system,
                       ip_addresses,open_alerts,owner,last_seen_at,is_simulated
                FROM inventory.vm_operational_overview
                WHERE (%s::text IS NULL OR site_key=%s) AND (%s::text IS NULL OR rack_key=%s)
                  AND (%s::text IS NULL OR server_key=%s)
                ORDER BY CASE health_status WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,name
            """, (site_key, site_key, rack_key, rack_key, server_key, server_key))
        elif operation == "server_connectivity":
            result = rows(connection, """
                SELECT site_key,site_name,server_key,server_name,rack_key,rack_name,server_interface,
                       mac_address::text mac_address,server_ip_addresses,switch_key,switch_name,switch_interface,
                       switch_vendor,switch_model,vlan_id,vlan_name,vrf_name,cidr::text cidr,gateway::text gateway,
                       upstream_core_01,upstream_core_02,upstream_firewall,upstream_router,
                       connection_status,redundancy_role,last_seen_at,is_simulated
                FROM inventory.server_network_attachment_overview
                WHERE (%s::text IS NULL OR site_key=%s) AND (%s::text IS NULL OR server_key=%s OR server_name=%s)
                ORDER BY CASE connection_status WHEN 'down' THEN 1 WHEN 'degraded' THEN 2 ELSE 3 END,site_name,server_name
            """, (site_key, site_key, server_key, server_key, server_key))
        elif operation == "connectivity_paths":
            result = rows(connection, """
                SELECT site_key,site_name,router,firewall,l3_switch,vlan_key,vlan_id,vrf_name,cidr::text cidr,
                       server_key,server_name,vm_key,vm_name,cluster_key,k8s_node,pod_name,pod_phase,
                       application_key,application_name,service_key,business_service,path_status
                FROM inventory.end_to_end_connectivity_paths
                WHERE (%s::text IS NULL OR site_key=%s) AND (%s::text IS NULL OR server_key=%s OR server_name=%s)
                ORDER BY CASE path_status WHEN 'at_risk' THEN 1 ELSE 2 END,site_name,server_name,pod_name
            """, (site_key, site_key, server_key, server_key, server_key))
        elif operation == "kubernetes":
            result = rows(connection, """
                SELECT s.site_key,s.name site_name,c.cluster_key,c.name cluster_name,c.distribution,c.version,
                       c.status cluster_status,n.name node_name,n.role,n.status node_status,ns.name namespace,
                       w.workload_type,w.name workload,w.desired_replicas,w.available_replicas,
                       p.name pod,p.phase,ct.name container,ct.image,ct.status container_status,p.last_seen_at,
                       p.is_simulated
                FROM inventory.k8s_clusters c JOIN inventory.sites s ON s.id=c.site_id
                LEFT JOIN inventory.k8s_nodes n ON n.cluster_id=c.id
                LEFT JOIN inventory.k8s_namespaces ns ON ns.cluster_id=c.id
                LEFT JOIN inventory.k8s_workloads w ON w.namespace_id=ns.id
                LEFT JOIN inventory.k8s_pods p ON p.workload_id=w.id
                LEFT JOIN inventory.k8s_containers ct ON ct.pod_id=p.id
                WHERE (%s::text IS NULL OR s.site_key=%s)
                ORDER BY s.name,c.name,ns.name,w.name,p.name
            """, filters)
        elif operation == "applications":
            result = rows(connection, """
                SELECT s.site_key,s.name site_name,a.application_key,a.name application,a.application_type,
                       a.environment,a.criticality,a.status,o.name owner,bs.name business_service,
                       ac.name component,ac.component_type,ac.runtime,ac.version,ac.status component_status,
                       a.updated_at,a.is_simulated
                FROM inventory.applications a
                JOIN inventory.application_sites aps ON aps.application_id=a.id
                JOIN inventory.sites s ON s.id=aps.site_id
                LEFT JOIN inventory.owners o ON o.id=a.owner_id
                LEFT JOIN inventory.application_components ac ON ac.application_id=a.id
                LEFT JOIN inventory.business_service_applications bsa ON bsa.application_id=a.id
                LEFT JOIN inventory.business_services bs ON bs.id=bsa.business_service_id
                WHERE (%s::text IS NULL OR s.site_key=%s)
                ORDER BY CASE a.criticality WHEN 'critical' THEN 1 WHEN 'high' THEN 2 ELSE 3 END,a.name,ac.name
            """, filters)
        elif operation == "alerts":
            result = rows(connection, """
                SELECT alert_key,entity_type,severity,status,title,description,metric_name,metric_value,
                       threshold_value,opened_at,is_simulated
                FROM events.inventory_alerts WHERE status<>'resolved'
                ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,opened_at DESC
            """)
        elif operation == "search":
            if not search_term or len(search_term.strip()) < 2:
                raise ValueError("search_term must contain at least two characters")
            pattern = f"%{search_term.strip()}%"
            result = rows(connection, """
                SELECT * FROM (
                  SELECT 'site' entity_type,site_key entity_key,name display_name,health_status status,NULL::text parent
                    FROM inventory.sites WHERE site_key ILIKE %s OR name ILIKE %s
                  UNION ALL
                  SELECT 'rack',r.rack_key,r.name,r.health_status,s.site_key
                    FROM inventory.racks r JOIN inventory.data_center_rows dr ON dr.id=r.row_id
                    JOIN inventory.rooms rm ON rm.id=dr.room_id JOIN inventory.sites s ON s.id=rm.site_id
                    WHERE r.rack_key ILIKE %s OR r.name ILIKE %s
                  UNION ALL
                  SELECT 'server',server_key,hostname,health_status,rack_key
                    FROM inventory.server_operational_overview WHERE server_key ILIKE %s OR hostname ILIKE %s
                  UNION ALL
                  SELECT 'virtual_machine',vm_key,name,health_status,server_key
                    FROM inventory.vm_operational_overview WHERE vm_key ILIKE %s OR name ILIKE %s OR hostname ILIKE %s
                  UNION ALL
                  SELECT 'application',application_key,name,status,environment
                    FROM inventory.applications WHERE application_key ILIKE %s OR name ILIKE %s
                ) found ORDER BY entity_type,display_name
            """, (pattern,) * 11)
        else:
            raise ValueError(f"unsupported operation: {operation}")
    return {"operation": operation, "row_count": len(result), "rows": result, "max_rows": MAX_ROWS}


SEMANTIC_ENTITIES: dict[str, dict[str, Any]] = {
    "data_centers": {
        "source": "inventory.data_center_operational_overview",
        "fields": ["site_key","name","region","environment","health_status","rack_count","server_count",
                   "vm_count","open_alerts","critical_alerts","unmonitored_assets","facility_power_used_kw",
                   "facility_power_capacity_kw","temperature_c","humidity_pct","pue","monitoring_coverage_pct",
                   "owner","last_seen_at","is_simulated"],
    },
    "racks": {
        "source": "inventory.rack_operational_overview",
        "fields": ["site_key","site_name","rack_key","name","room_name","row_name","health_status","rack_units",
                   "used_rack_units","max_power_watts","current_power_watts","temperature_c","humidity_pct",
                   "monitoring_status","server_count","vm_count","open_alerts","updated_at","is_simulated"],
    },
    "servers": {
        "source": "inventory.server_operational_overview",
        "fields": ["site_key","site_name","rack_key","rack_name","server_key","hostname","health_status","status",
                   "environment","criticality","monitoring_status","manufacturer","model","operating_system",
                   "physical_cores","logical_processors","ram_bytes","local_storage_bytes","gpu_count",
                   "cpu_utilization_percent","memory_utilization_percent","disk_utilization_percent",
                   "temperature_celsius","power_consumption_watts","uptime_percent","available","vm_count",
                   "open_alerts","owner","business_service","warranty_expiry","end_of_support","last_seen_at",
                   "is_simulated"],
    },
    "virtual_machines": {
        "source": "inventory.vm_operational_overview",
        "fields": ["site_key","site_name","rack_key","rack_name","server_key","physical_host","vm_key","name",
                   "hostname","health_status","status","environment","criticality","monitoring_status","vcpu_count",
                   "memory_bytes","provisioned_storage_bytes","cpu_utilization_pct","memory_utilization_pct",
                   "storage_utilization_pct","uptime_pct","snapshot_count","backup_status","operating_system",
                   "open_alerts","owner","last_seen_at","is_simulated"],
    },
    "kubernetes_pods": {
        "source": "(SELECT s.site_key,s.name site_name,c.cluster_key,c.name cluster_name,ns.name namespace,"
                  "w.workload_type,w.name workload,p.name pod_name,p.phase,n.name node_name,p.qos_class,"
                  "p.last_seen_at,p.is_simulated "
                  "FROM inventory.k8s_pods p JOIN inventory.k8s_workloads w ON w.id=p.workload_id "
                  "JOIN inventory.k8s_namespaces ns ON ns.id=w.namespace_id "
                  "JOIN inventory.k8s_clusters c ON c.id=ns.cluster_id JOIN inventory.sites s ON s.id=c.site_id "
                  "LEFT JOIN inventory.k8s_nodes n ON n.id=p.node_id) semantic_pods",
        "fields": ["site_key","site_name","cluster_key","cluster_name","namespace","workload_type","workload",
                   "pod_name","phase","node_name","qos_class","last_seen_at","is_simulated"],
    },
    "applications": {
        "source": "(SELECT DISTINCT s.site_key,s.name site_name,a.application_key,a.name application,a.application_type,"
                  "a.environment,a.criticality,a.status,o.name owner,bs.name business_service,a.updated_at,a.is_simulated "
                  "FROM inventory.applications a JOIN inventory.application_sites aps ON aps.application_id=a.id "
                  "JOIN inventory.sites s ON s.id=aps.site_id LEFT JOIN inventory.owners o ON o.id=a.owner_id "
                  "LEFT JOIN inventory.business_service_applications bsa ON bsa.application_id=a.id "
                  "LEFT JOIN inventory.business_services bs ON bs.id=bsa.business_service_id) semantic_apps",
        "fields": ["site_key","site_name","application_key","application","application_type","environment",
                   "criticality","status","owner","business_service","updated_at","is_simulated"],
    },
    "alerts": {
        "source": "events.inventory_alerts",
        "fields": ["alert_key","entity_type","severity","status","title","description","metric_name","metric_value",
                   "threshold_value","opened_at","is_simulated"],
    },
    "server_connectivity": {
        "source": "inventory.server_network_attachment_overview",
        "fields": ["site_key","site_name","server_key","server_name","rack_key","rack_name","server_interface",
                   "mac_address","server_ip_addresses","switch_key","switch_name","switch_interface",
                   "switch_vendor","switch_model","vlan_id","vlan_name","vrf_name","cidr","gateway",
                   "connection_status","redundancy_role","upstream_core_01","upstream_core_02",
                   "upstream_firewall","upstream_router","last_seen_at","is_simulated"],
    },
    "connectivity_paths": {
        "source": "inventory.end_to_end_connectivity_paths",
        "fields": ["site_key","site_name","router","firewall","l3_switch","vlan_key","vlan_id","vrf_name",
                   "cidr","server_key","server_name","vm_key","vm_name","cluster_key","k8s_node","pod_name",
                   "pod_phase","application_key","application_name","service_key","business_service","path_status"],
    },
}


def inventory_semantic_query(
    entity: str,
    mode: str,
    fields: list[str] | None = None,
    group_by: list[str] | None = None,
    metric: str = "count",
    metric_field: str | None = None,
    filters: list[dict[str, Any]] | None = None,
    distinct: bool = False,
    order_by: str | None = None,
    order_direction: str = "asc",
    limit: int = 25,
) -> dict[str, Any]:
    """Build a parameterized read-only query exclusively from allowlisted semantic metadata."""
    if entity not in SEMANTIC_ENTITIES:
        raise ValueError(f"unsupported entity {entity!r}")
    metadata = SEMANTIC_ENTITIES[entity]
    allowed = set(metadata["fields"])
    selected = fields or []
    grouped = group_by or []
    for field in [*selected, *grouped]:
        if field not in allowed:
            raise ValueError(f"field {field!r} is not allowed for {entity}; allowed fields: {sorted(allowed)}")
    if mode not in {"list", "aggregate"}:
        raise ValueError("mode must be list or aggregate")
    if metric not in {"count", "distinct_count", "sum", "avg", "min", "max"}:
        raise ValueError("unsupported metric")
    if metric != "count" and (not metric_field or metric_field not in allowed):
        raise ValueError(f"metric_field is required and must be allowed for metric {metric}")
    safe_limit = max(1, min(int(limit), MAX_ROWS))
    params: list[Any] = []
    where_parts: list[sql.Composable] = []
    for item in filters or []:
        field = item.get("field")
        operator = item.get("operator", "eq")
        value = item.get("value")
        if field not in allowed:
            raise ValueError(f"filter field {field!r} is not allowed for {entity}")
        identifier = sql.Identifier(field)
        if operator in {"eq", "ne", "gt", "gte", "lt", "lte"}:
            symbols = {"eq": "=", "ne": "<>", "gt": ">", "gte": ">=", "lt": "<", "lte": "<="}
            where_parts.append(sql.SQL("{} {} %s").format(identifier, sql.SQL(symbols[operator])))
            params.append(value)
        elif operator == "contains":
            where_parts.append(sql.SQL("CAST({} AS text) ILIKE %s").format(identifier))
            params.append(f"%{value}%")
        elif operator == "in":
            values = value if isinstance(value, list) else [value]
            if not values:
                raise ValueError("in filter requires at least one value")
            where_parts.append(sql.SQL("{} = ANY(%s)").format(identifier))
            params.append(values)
        else:
            raise ValueError(f"unsupported filter operator {operator!r}")

    if mode == "list":
        output_fields = selected or metadata["fields"][:8]
        select_clause = sql.SQL(",").join(sql.Identifier(field) for field in output_fields)
        distinct_clause = sql.SQL("DISTINCT ") if distinct else sql.SQL("")
    else:
        output_fields = grouped
        group_items = [sql.Identifier(field) for field in grouped]
        if metric == "count":
            metric_expression = sql.SQL("count(*)")
        elif metric == "distinct_count":
            metric_expression = sql.SQL("count(DISTINCT {})").format(sql.Identifier(metric_field))
        else:
            metric_expression = sql.SQL("{}({})").format(sql.SQL(metric), sql.Identifier(metric_field))
        select_clause = sql.SQL(",").join([*group_items, sql.SQL("{} AS value").format(metric_expression)])
        distinct_clause = sql.SQL("")

    query = sql.SQL("SELECT {}{} FROM {}").format(distinct_clause, select_clause, sql.SQL(metadata["source"]))
    if where_parts:
        query += sql.SQL(" WHERE ") + sql.SQL(" AND ").join(where_parts)
    if mode == "aggregate" and grouped:
        query += sql.SQL(" GROUP BY ") + sql.SQL(",").join(sql.Identifier(field) for field in grouped)
    allowed_order = set(output_fields) | ({"value"} if mode == "aggregate" else set())
    if order_by:
        if order_by not in allowed_order:
            raise ValueError(f"order_by must be one of {sorted(allowed_order)}")
        direction = sql.SQL("DESC") if order_direction.casefold() == "desc" else sql.SQL("ASC")
        query += sql.SQL(" ORDER BY {} {}").format(sql.Identifier(order_by), direction)
    query += sql.SQL(" LIMIT %s")
    params.append(safe_limit)
    with database() as connection:
        result = rows(connection, query, tuple(params))
    return {
        "entity": entity, "mode": mode, "row_count": len(result), "rows": result,
        "limit": safe_limit, "may_be_truncated": len(result) == safe_limit,
        "is_read_only": True,
    }


TOOLS = [{
    "type": "function",
    "function": {
        "name": "inventory_query",
        "description": "Read approved ARDMATRIX inventory and health views. Use this before answering inventory questions.",
        "parameters": {
            "type": "object",
            "properties": {
                "operation": {"type": "string", "enum": ["summary","sites","racks","servers","virtual_machines","kubernetes","applications","alerts","search","server_vendors","server_models","pod_health","server_connectivity","connectivity_paths"]},
                "site_key": {"type": ["string","null"]},
                "rack_key": {"type": ["string","null"]},
                "server_key": {"type": ["string","null"]},
                "search_term": {"type": ["string","null"]}
            },
            "required": ["operation","site_key","rack_key","server_key","search_term"],
            "additionalProperties": False
        },
    }
}, {
    "type": "function",
    "function": {
        "name": "inventory_semantic_query",
        "description": (
            "Generic read-only inventory analytics. Prefer this for lists, unique values, grouping, comparisons, "
            "averages, sums, and filtered questions. Entities and common fields: data_centers(site_key,name,region,"
            "environment,health_status,rack_count,server_count,vm_count,open_alerts,critical_alerts,pue,owner); "
            "racks(site_key,rack_key,name,health_status,rack_units,used_rack_units,current_power_watts,temperature_c,"
            "server_count,vm_count,open_alerts); servers(site_key,rack_key,server_key,hostname,health_status,status,"
            "environment,criticality,manufacturer,model,operating_system,physical_cores,ram_bytes,gpu_count,"
            "cpu_utilization_percent,memory_utilization_percent,disk_utilization_percent,temperature_celsius,"
            "power_consumption_watts,uptime_percent,vm_count,open_alerts,owner,business_service); virtual_machines("
            "site_key,rack_key,server_key,physical_host,vm_key,name,health_status,status,environment,criticality,"
            "vcpu_count,memory_bytes,cpu_utilization_pct,memory_utilization_pct,storage_utilization_pct,backup_status,"
            "operating_system,open_alerts,owner); kubernetes_pods(site_key,cluster_key,cluster_name,namespace,workload,"
            "pod_name,phase,node_name,qos_class,last_seen_at); applications("
            "site_key,application_key,application,application_type,environment,criticality,status,owner,business_service); "
            "alerts(entity_type,severity,status,title,metric_name,metric_value,threshold_value,opened_at); "
            "server_connectivity(site_key,server_key,server_name,rack_name,server_interface,mac_address,"
            "server_ip_addresses,switch_name,switch_interface,switch_vendor,switch_model,vlan_id,vlan_name,vrf_name,"
            "cidr,gateway,connection_status,upstream_core_01,upstream_core_02,upstream_firewall,upstream_router); "
            "connectivity_paths(site_key,router,firewall,l3_switch,vlan_id,vrf_name,cidr,server_key,server_name,"
            "vm_name,cluster_key,k8s_node,pod_name,pod_phase,application_name,business_service,path_status)."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "entity": {"type": "string", "enum": ["data_centers","racks","servers","virtual_machines","kubernetes_pods","applications","alerts","server_connectivity","connectivity_paths"]},
                "mode": {"type": "string", "enum": ["list","aggregate"]},
                "fields": {"type": "array", "items": {"type": "string"}},
                "group_by": {"type": "array", "items": {"type": "string"}},
                "metric": {"type": "string", "enum": ["count","distinct_count","sum","avg","min","max"]},
                "metric_field": {"type": ["string","null"]},
                "filters": {"type": "array", "items": {"type": "object", "properties": {
                    "field": {"type": "string"},
                    "operator": {"type": "string", "enum": ["eq","ne","in","contains","gt","gte","lt","lte"]},
                    "value": {}
                }, "required": ["field","operator","value"], "additionalProperties": False}},
                "distinct": {"type": "boolean"},
                "order_by": {"type": ["string","null"]},
                "order_direction": {"type": "string", "enum": ["asc","desc"]},
                "limit": {"type": "integer", "minimum": 1, "maximum": 50}
            },
            "required": ["entity","mode","fields","group_by","metric","metric_field","filters","distinct","order_by","order_direction","limit"],
            "additionalProperties": False
        }
    }
}]

INSTRUCTIONS = """You are ARDMATRIX AIOps Expert for technical operations.
Always use one or more inventory tools before answering an inventory question. Prefer inventory_semantic_query for
unique lists, grouping, filtering, comparisons, averages, totals, rankings, and combinations of fields. Use
inventory_query for hierarchy detail, summary, search, or its purpose-built operational views. If initial evidence is
insufficient, call another relevant tool instead of ending with an unanswered question. Tool validation errors are
instructions to correct the arguments and retry. Never invent counts, state, ownership, capacity, alerts, topology,
or relationships. State when results are simulated and mention truncation. Answer the exact requested scope; do not
replace a requested list with a summary. Ask one concise clarification only when the user's meaning is genuinely
ambiguous after using available evidence. Keep answers concise and use clear units. Do not expose SQL, credentials,
UUIDs, tool schemas, or implementation details. The tools are read-only and already enforce authorization boundaries."""


@app.get("/health")
def health() -> dict[str, Any]:
    database_ok = False
    llm_ok = (
        len(LLM_API_KEY) > 20
        and LLM_API_KEY.startswith("sk-")
        and "your-" not in LLM_API_KEY.casefold()
    )
    try:
        with database() as connection:
            database_ok = connection.execute("SELECT 1").fetchone()[0] == 1
    except Exception:
        database_ok = False
    return {"status": "ok" if database_ok and llm_ok else "degraded", "database": database_ok,
            "llm_configured": llm_ok, "model": LLM_MODEL, "provider": LLM_PROVIDER}


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    fast_answer = fast_inventory_answer(request.message)
    if fast_answer is not None:
        return fast_answer
    if not LLM_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="OpenAI is not configured. Add OPENAI_API_KEY to .env and restart inventory-assistant.",
        )
    client = OpenAI(api_key=LLM_API_KEY, base_url=LLM_BASE_URL)
    messages: list[dict[str, Any]] = [{"role": "system", "content": INSTRUCTIONS}]
    for item in request.history:
        if item.get("role") in {"user", "assistant"} and item.get("content"):
            messages.append({"role": item["role"], "content": item["content"][:4000]})
    messages.append({"role": "user", "content": request.message})
    tools_used: list[str] = []
    for _ in range(4):
        try:
            request_options: dict[str, Any] = {
                "model": LLM_MODEL, "messages": messages, "tools": TOOLS,
                "tool_choice": "auto", "max_completion_tokens": MAX_COMPLETION_TOKENS,
            }
            if LLM_PROVIDER == "openai":
                request_options["reasoning_effort"] = LLM_REASONING_EFFORT
            completion = client.chat.completions.create(**request_options)
        except Exception as exc:
            provider_issue = type(exc).__name__
            if provider_issue == "RateLimitError":
                return ChatResponse(
                    answer=("OpenAI is temporarily rate-limited or the API account has no available quota. "
                            "AIOps Expert is still available in database-only mode for inventory totals, server "
                            "vendors/models, pod health, and exact server-connectivity questions. For connectivity, "
                            "ask: `Which switch port is server srv-bengaluru-01-01 connected to?`"),
                    tools_used=["provider_fallback:database-only"], model="database-fast-path"
                )
            return ChatResponse(
                answer=("The language-model service is temporarily unavailable. Database-backed inventory and "
                        "server-connectivity queries remain available; please retry this question shortly."),
                tools_used=["provider_fallback:database-only"], model="database-fast-path"
            )
        message = completion.choices[0].message
        calls = message.tool_calls or []
        if not calls:
            return ChatResponse(answer=message.content or "No answer was generated.",
                                tools_used=tools_used, model=LLM_MODEL)
        messages.append(message.model_dump(exclude_none=True))
        for call in calls:
            try:
                arguments = json.loads(call.function.arguments)
                if call.function.name == "inventory_query":
                    result = inventory_query(**arguments)
                    tool_label = f"inventory_query:{arguments['operation']}"
                elif call.function.name == "inventory_semantic_query":
                    result = inventory_semantic_query(**arguments)
                    tool_label = f"inventory_semantic_query:{arguments['entity']}:{arguments['mode']}"
                else:
                    raise ValueError(f"unsupported tool {call.function.name}")
                tools_used.append(tool_label)
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                result = {"error": str(exc), "retry_with_corrected_arguments": True}
            messages.append({"role": "tool", "tool_call_id": call.id,
                             "content": json.dumps(result, default=str)})
    raise HTTPException(status_code=502, detail="Assistant exceeded the tool-call limit")
