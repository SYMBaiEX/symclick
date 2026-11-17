"""Validate the public report contract without posting mouse events."""
import json
import sys
import subprocess

report = json.loads(subprocess.check_output([sys.argv[1], "--performance-report"], text=True))
assert set(report) == {
    "schema", "version", "architecture", "accessibility", "configuration",
    "timing_mode", "observed_throughput",
}
assert report["schema"] == "symclick-performance/v1"
assert report["accessibility"] in {"granted", "not-granted"}
assert report["timing_mode"] == "mach-absolute-deadlines"
assert report["observed_throughput"] is None
config = report["configuration"]
assert set(config) == {
    "cps", "limit_mode", "click_limit", "duration_seconds", "start_delay_seconds",
    "cps_min", "cps_max", "click_limit_max", "duration_seconds_max",
}
assert config["limit_mode"] in {"unlimited", "click-count", "duration"}
assert config["cps_min"] <= config["cps"] <= config["cps_max"]
assert 1 <= config["click_limit"] <= config["click_limit_max"]
assert 1 <= config["duration_seconds"] <= config["duration_seconds_max"]
assert 0 <= config["start_delay_seconds"] <= 10
