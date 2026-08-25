CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS telemetry;
CREATE SCHEMA IF NOT EXISTS events;
CREATE SCHEMA IF NOT EXISTS ai;

COMMENT ON SCHEMA inventory IS 'Sites, assets, applications, services, and topology';
COMMENT ON SCHEMA telemetry IS 'Normalized and derived operational measurements';
COMMENT ON SCHEMA events IS 'Alerts, incidents, correlations, and RCA events';
COMMENT ON SCHEMA ai IS 'Models, anomaly results, forecasts, and AI findings';
