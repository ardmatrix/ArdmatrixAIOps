-- Customer-demo failure scenario: two physical servers down in Chicago Rack 02.
-- The topology and summaries derive their state directly from these inventory fields.
UPDATE inventory.servers
SET status='failed',
    health_status='critical',
    attributes=attributes||jsonb_build_object(
      'failure_scenario','simulated power supply failure',
      'incident_id','INC-DCCHI-R02-001',
      'alarm_severity','critical'
    ),
    last_seen_at=now()-interval '8 minutes',
    updated_at=now()
WHERE server_key IN ('dc-chicago-rack-02-srv-09','dc-chicago-rack-02-srv-10');

INSERT INTO events.inventory_alerts
  (id,alert_key,entity_type,entity_id,severity,status,title,description,
   opened_at,is_simulated,attributes)
SELECT md5('alert-'||sv.server_key||'-down')::uuid,
       'server-down-'||sv.server_key,'server',sv.id,'critical','open',
       'Physical server unavailable',
       sv.hostname||' is unreachable from monitoring and both management paths.',
       now()-interval '8 minutes',true,
       jsonb_build_object('incident_id','INC-DCCHI-R02-001','probable_cause','power supply failure')
FROM inventory.servers sv
WHERE sv.server_key IN ('dc-chicago-rack-02-srv-09','dc-chicago-rack-02-srv-10')
ON CONFLICT (alert_key) DO UPDATE SET
  severity='critical',status='open',title=EXCLUDED.title,
  description=EXCLUDED.description,opened_at=EXCLUDED.opened_at,
  is_simulated=true,attributes=EXCLUDED.attributes;
