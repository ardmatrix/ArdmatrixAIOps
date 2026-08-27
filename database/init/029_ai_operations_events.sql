BEGIN;

CREATE TABLE IF NOT EXISTS ai.anomalies (
    event_id uuid PRIMARY KEY,
    observed_at timestamptz NOT NULL,
    site_id text,
    asset_id text,
    metric_name text NOT NULL,
    actual_value double precision,
    baseline_value double precision,
    anomaly_score double precision,
    severity text NOT NULL,
    model_name text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS ai.forecasts (
    event_id uuid PRIMARY KEY,
    generated_at timestamptz NOT NULL,
    site_id text,
    asset_id text,
    metric_name text NOT NULL,
    horizon_hours integer NOT NULL,
    predicted_value double precision,
    threshold_value double precision,
    predicted_breach_at timestamptz,
    confidence double precision,
    model_name text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS events.correlated_incidents (
    event_id uuid PRIMARY KEY,
    incident_key text NOT NULL UNIQUE,
    started_at timestamptz NOT NULL,
    site_id text,
    severity text NOT NULL,
    status text NOT NULL,
    root_asset_id text,
    correlated_event_count integer NOT NULL DEFAULT 0,
    impacted_services text[] NOT NULL DEFAULT '{}',
    summary text NOT NULL,
    correlation_confidence double precision,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS ai.rca_findings (
    event_id uuid PRIMARY KEY,
    incident_key text NOT NULL,
    generated_at timestamptz NOT NULL,
    site_id text,
    root_asset_id text,
    probable_cause text NOT NULL,
    confidence double precision,
    service_impact text,
    evidence text[] NOT NULL DEFAULT '{}',
    recommendation text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS anomalies_time_idx ON ai.anomalies(observed_at DESC);
CREATE INDEX IF NOT EXISTS forecasts_time_idx ON ai.forecasts(generated_at DESC);
CREATE INDEX IF NOT EXISTS incidents_time_idx ON events.correlated_incidents(started_at DESC);
CREATE INDEX IF NOT EXISTS rca_time_idx ON ai.rca_findings(generated_at DESC);

COMMIT;
