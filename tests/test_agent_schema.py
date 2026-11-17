#!/usr/bin/env python3
"""Validate the published event schema, documentation, and safe live responses.

Requires the development-only Python jsonschema package; never runs clicks.
"""
import copy
import json
from pathlib import Path
import re
import subprocess

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
schema = json.loads((ROOT / "schemas/symclick-agent-v1.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)

examples = re.findall(r"```json\s*\n(.*?)\n```", (ROOT / "docs/AGENT_INTEGRATION.md").read_text(), re.S)
assert examples, "No JSON examples found"
for example in examples:
    validator.validate(json.loads(example))

binary = ROOT / "build/SymClick.app/Contents/MacOS/SymClick"
def command(*args, expected=0):
    result = subprocess.run([str(binary), *args], text=True, capture_output=True)
    assert result.returncode == expected, result.stderr
    event = json.loads(result.stdout)
    validator.validate(event)
    return event

command("--agent-status")
plan = command("--agent-validate", "--x", "-2.5", "--y", "200", "--clicks", "3", "--cps", "100")
command("--agent-validate", "--x", "0", "--y", "0", "--duration", "1.5")
command("--agent-validate", expected=2)
for name in ("ready",):
    event = dict(plan, event=name)
    validator.validate(event)
for event in (
    {"protocol":"symclick-agent/v1", "event":"started"},
    {"protocol":"symclick-agent/v1", "event":"completed", "clicks":0, "reason":"duration-limit"},
    {"protocol":"symclick-agent/v1", "event":"error", "code":"accessibility_required", "message":"Permission required"},
):
    validator.validate(event)
for change in ({"protocol":"symclick-agent/v2"}, {"event":"unknown"}, {"bound":{"type":"clicks", "value":0}}, {"bound":{"type":"duration_seconds", "value":86401}}):
    invalid = copy.deepcopy(plan)
    invalid.update(change)
    assert not validator.is_valid(invalid), invalid
validator.validate(dict(plan, future_optional_field=True))
print("Agent schema and examples validated")
