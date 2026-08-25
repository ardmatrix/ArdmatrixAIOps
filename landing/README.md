# Landing zone

Collectors place incoming files into the source-specific directories here.
The ingestion service will validate, normalize, deduplicate, and enrich them.
Rejected records are routed to `errors/` with a machine-readable reason.

Runtime landing files are intentionally ignored by Git. The `.gitkeep` files
preserve the required directory structure.
