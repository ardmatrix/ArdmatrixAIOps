BEGIN;

CREATE TABLE IF NOT EXISTS ingestion.simulator_runs (
    run_key text PRIMARY KEY,
    started_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    interval_seconds integer NOT NULL CHECK (interval_seconds >= 10),
    last_emitted_at timestamptz,
    batch_count integer NOT NULL DEFAULT 0,
    event_count bigint NOT NULL DEFAULT 0,
    error_count bigint NOT NULL DEFAULT 0,
    status text NOT NULL CHECK (status IN ('running','completed','stopped')),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;
