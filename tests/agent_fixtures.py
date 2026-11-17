#!/usr/bin/env python3
"""Check protocol fixtures and read-only CLI responses without posting events."""

import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures" / "agent-v1"
PROTOCOL = "symclick-agent/v1"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load_fixture(name):
    lines = (FIXTURES / f"{name}.jsonl").read_text(encoding="utf-8").splitlines()
    require(bool(lines), f"{name}: empty fixture")
    events = [json.loads(line) for line in lines]
    for event in events:
        require(isinstance(event, dict) and event.get("protocol") == PROTOCOL,
                f"{name}: invalid protocol")
        require(isinstance(event.get("event"), str), f"{name}: missing event")
    return events


def check_config(event, expected_event):
    require(event.get("event") == expected_event and event.get("valid") is True,
            f"{expected_event}: invalid event or valid flag")
    target = event.get("target")
    require(isinstance(target, dict) and all(isinstance(target.get(k), (int, float)) for k in ("x", "y")),
            f"{expected_event}: target must contain numeric x and y")
    for key in ("cps", "jitter", "start_delay_seconds"):
        require(isinstance(event.get(key), (int, float)), f"{expected_event}: missing numeric {key}")
    require(event.get("button") in ("left", "right", "middle"), "invalid button")
    require(event.get("pattern") in ("single", "double"), "invalid pattern")
    bound = event.get("bound")
    require(isinstance(bound, dict) and bound.get("type") in ("clicks", "duration_seconds")
            and isinstance(bound.get("value"), (int, float)), "invalid bound")


def invoke(binary, args, expected_exit):
    result = subprocess.run([binary, *args], capture_output=True, text=True, check=False)
    require(result.returncode == expected_exit,
            f"{args[0]}: expected exit {expected_exit}, got {result.returncode}: {result.stderr}")
    lines = result.stdout.splitlines()
    require(len(lines) == 1, f"{args[0]}: expected one JSONL event")
    return json.loads(lines[0])


def main(binary):
    status = load_fixture("status")[0]
    require(status["event"] == "status" and status["local_only"] is True,
            "status fixture is invalid")
    require(all(isinstance(status.get(key), str) for key in ("version", "machine", "accessibility")),
            "status fixture missing string fields")
    require(status["accessibility"] in ("granted", "not-granted") and
            status["capabilities"] == ["inspect", "validate", "run"], "status fixture has invalid values")

    for name in ("validate-clicks", "validate-duration"):
        events = load_fixture(name)
        require(len(events) == 1, f"{name}: expected one event")
        check_config(events[0], "validated")
    for name, reason in (("run-clicks", "click-limit"), ("run-duration", "duration-limit")):
        events = load_fixture(name)
        require([event["event"] for event in events] == ["ready", "started", "completed"],
                f"{name}: incorrect event sequence")
        check_config(events[0], "ready")
        require(events[2].get("reason") == reason and isinstance(events[2].get("clicks"), int),
                f"{name}: invalid completion")
    for name, code in (("invalid-request", "invalid_request"),
                       ("accessibility-required", "accessibility_required")):
        events = load_fixture(name)
        require(len(events) == 1 and events[0].get("event") == "error" and
                events[0].get("code") == code and isinstance(events[0].get("message"), str),
                f"{name}: invalid error")

    live_status = invoke(binary, ["--agent-status"], 0)
    require(set(status) <= set(live_status) and live_status["protocol"] == PROTOCOL and
            live_status["event"] == "status" and live_status["local_only"] is True and
            live_status["accessibility"] in ("granted", "not-granted") and
            live_status["capabilities"] == status["capabilities"], "live status contract changed")
    cases = (
        ("validate-clicks", ["--agent-validate", "--x", "100", "--y", "200", "--clicks", "3", "--cps", "100"]),
        ("validate-duration", ["--agent-validate", "--x", "-50", "--y", "40", "--duration", "5", "--button", "right", "--pattern", "double", "--jitter", "2", "--delay", "0"]),
    )
    for name, args in cases:
        require(invoke(binary, args, 0) == load_fixture(name)[0], f"{name}: output differs from fixture")
    invalid = invoke(binary, ["--agent-run", "--x", "100", "--y", "200", "--clicks", "3"], 2)
    require(invalid == load_fixture("invalid-request")[0], "invalid request output differs from fixture")
    print("Agent v1 fixtures and no-click CLI checks passed")


if __name__ == "__main__":
    require(len(sys.argv) == 2, "usage: agent_fixtures.py <SymClick binary>")
    main(sys.argv[1])
