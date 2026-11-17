#!/usr/bin/env python3
"""Exercise the local agent interface without ever generating mouse input."""

import json
import subprocess
import sys
import unittest
from pathlib import Path


if len(sys.argv) != 2:
    raise SystemExit("usage: agent_contract.py PATH_TO_SYMCLICK_BINARY")
BINARY = str(Path(sys.argv.pop()).resolve())
PROTOCOL = "symclick-agent/v1"


class AgentContractTests(unittest.TestCase):
    def invoke(self, *arguments, exit_code=0):
        result = subprocess.run(
            [BINARY, *arguments], capture_output=True, text=True, timeout=10, check=False
        )
        self.assertEqual(
            result.returncode, exit_code,
            f"{arguments}: expected exit {exit_code}, got {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}",
        )
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"{arguments}: invalid JSON output: {error}; stdout={result.stdout!r}")
        self.assertEqual(payload.get("protocol"), PROTOCOL, arguments)
        return payload

    def test_help_advertises_safe_contract(self):
        payload = self.invoke("--agent-help")
        self.assertTrue(payload["safety"]["requires_confirmation"])
        self.assertTrue(payload["safety"]["requires_fixed_target"])
        self.assertTrue(payload["safety"]["requires_finite_bound"])
        self.assertEqual(payload["events"], ["status", "inspection", "validated", "error"])

    def test_real_agent_run_fails_closed(self):
        payload = self.invoke("--agent-run", "--confirm", "--x", "0", "--y", "0",
                              "--clicks", "1", exit_code=4)
        self.assertEqual(payload["code"], "run_unavailable")

    def test_status_reports_permission_without_prompting(self):
        payload = self.invoke("--agent-status")
        self.assertEqual(payload["event"], "status")
        self.assertIn(payload["accessibility"], ("granted", "not-granted"))
        self.assertTrue(payload["local_only"])

    def test_validated_plan_reports_normalized_values(self):
        payload = self.invoke("--agent-validate", "--x", "-100", "--y", "200",
                              "--clicks", "3", "--cps", "24.6", "--delay", "2.6")
        self.assertEqual(payload["event"], "validated")
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["target"], {"x": -100, "y": 200})
        self.assertEqual(payload["cps"], 25)
        self.assertEqual(payload["start_delay_seconds"], 3)
        self.assertEqual(payload["bound"], {"type": "clicks", "value": 3})

    def test_invalid_requests_return_structured_error(self):
        cases = (
            ("--agent-validate", "--x", "0", "--y", "0"),
            ("--agent-validate", "--x", "nan", "--y", "0", "--clicks", "1"),
            ("--agent-validate", "--x", "0", "--y", "0", "--clicks", "0"),
            ("--agent-validate", "--x", "0", "--y", "0", "--clicks", "1", "--duration", "1"),
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                payload = self.invoke(*arguments, exit_code=2)
                self.assertEqual(payload["event"], "error")
                self.assertEqual(payload["code"], "invalid_request")
                self.assertTrue(payload["message"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
