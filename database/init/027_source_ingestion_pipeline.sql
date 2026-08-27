BEGIN;

CREATE SCHEMA IF NOT EXISTS ingestion;

CREATE TABLE IF NOT EXISTS ingestion.source_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_id uuid NOT NULL UNIQUE,
    source_type text NOT NULL CHECK (source_type IN ('csv','json','api','telemetry','snmp','log')),
    source_system text NOT NULL,
    topic text NOT NULL,
    event_type text NOT NULL,
    asset_id text,
    site_id text,
    status text NOT NULL CHECK (status IN ('received','published','rejected')),
    is_simulated boolean NOT NULL DEFAULT false,
    observed_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    error_code text,
    error_message text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS source_events_received_idx
    ON ingestion.source_events(received_at DESC);
CREATE INDEX IF NOT EXISTS source_events_source_idx
    ON ingestion.source_events(source_type, status, received_at DESC);
CREATE INDEX IF NOT EXISTS source_events_topic_idx
    ON ingestion.source_events(topic, received_at DESC);

CREATE OR REPLACE VIEW ingestion.source_health AS
SELECT source_type,
       source_system,
       count(*) FILTER (WHERE status = 'received') AS received,
       count(*) FILTER (WHERE status = 'published') AS published,
       count(*) FILTER (WHERE status = 'rejected') AS rejected,
       max(received_at) AS last_received_at,
       max(published_at) AS last_published_at,
       max(error_message) FILTER (WHERE status = 'rejected') AS latest_error
FROM ingestion.source_events
GROUP BY source_type, source_system;

COMMIT;
