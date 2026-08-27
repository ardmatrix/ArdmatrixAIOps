from unittest import TestCase

from app.pipeline import ValidationError, normalize_event


class PipelineTests(TestCase):
    def test_normalizes_snmp_event(self) -> None:
        event = normalize_event("snmp", {
            "source_system": "dc-chicago-snmp",
            "asset_id": "chi-core-01",
            "site_id": "dc-chicago",
            "payload": {"interface": "Gi1/0/1", "oper_status": "down"},
        })
        self.assertEqual(event["topic"], "network.metrics")
        self.assertEqual(event["source_type"], "snmp")
        self.assertFalse(event["is_simulated"])

    def test_rejects_arbitrary_topic(self) -> None:
        with self.assertRaises(ValidationError):
            normalize_event("api", {"source_system": "test", "topic": "unsafe.topic", "payload": {}})
