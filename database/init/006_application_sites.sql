CREATE TABLE IF NOT EXISTS inventory.application_sites (
    application_id uuid NOT NULL REFERENCES inventory.applications(id) ON DELETE CASCADE,
    site_id uuid NOT NULL REFERENCES inventory.sites(id) ON DELETE CASCADE,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (application_id, site_id)
);

CREATE INDEX IF NOT EXISTS application_sites_site_idx
    ON inventory.application_sites(site_id);

INSERT INTO inventory.application_sites (application_id, site_id, is_primary)
SELECT a.id, s.id, true
FROM inventory.applications a
JOIN inventory.sites s ON s.site_key = 'dc-bengaluru'
WHERE a.application_key = 'crm-application'
ON CONFLICT (application_id, site_id) DO UPDATE
SET is_primary = EXCLUDED.is_primary;
