BEGIN;

CREATE SCHEMA IF NOT EXISTS ingestion;

CREATE TABLE IF NOT EXISTS ingestion.file_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name text NOT NULL,
    entity_type text NOT NULL,
    sha256 text NOT NULL,
    file_size_bytes bigint NOT NULL CHECK (file_size_bytes >= 0),
    status text NOT NULL CHECK (status IN
        ('received','validating','published','completed','duplicate','rejected')),
    rows_received integer NOT NULL DEFAULT 0 CHECK (rows_received >= 0),
    rows_published integer NOT NULL DEFAULT 0 CHECK (rows_published >= 0),
    rows_processed integer NOT NULL DEFAULT 0 CHECK (rows_processed >= 0),
    rows_rejected integer NOT NULL DEFAULT 0 CHECK (rows_rejected >= 0),
    error_summary text,
    received_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    published_at timestamptz,
    completed_at timestamptz,
    archive_path text,
    UNIQUE (entity_type, sha256)
);

CREATE TABLE IF NOT EXISTS ingestion.row_errors (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    file_run_id uuid NOT NULL REFERENCES ingestion.file_runs(id) ON DELETE CASCADE,
    row_number integer,
    field_name text,
    field_value text,
    error_code text NOT NULL,
    error_message text NOT NULL,
    row_data jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ingestion.processed_messages (
    message_id text PRIMARY KEY,
    file_run_id uuid NOT NULL REFERENCES ingestion.file_runs(id) ON DELETE CASCADE,
    entity_type text NOT NULL,
    entity_id uuid,
    processed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_runs_received_idx
    ON ingestion.file_runs(received_at DESC);
CREATE INDEX IF NOT EXISTS file_runs_status_idx
    ON ingestion.file_runs(status);
CREATE INDEX IF NOT EXISTS row_errors_file_run_idx
    ON ingestion.row_errors(file_run_id, row_number);

CREATE OR REPLACE VIEW ingestion.file_run_summary AS
SELECT id, file_name, entity_type, status, rows_received, rows_published,
       rows_processed, rows_rejected, received_at, completed_at, error_summary
FROM ingestion.file_runs
ORDER BY received_at DESC;

COMMIT;
