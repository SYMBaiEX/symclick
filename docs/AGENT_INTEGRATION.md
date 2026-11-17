# SymClick local agent integration

SymClick v1.3 introduces a small local command contract for AI agents and other
automation clients. It is intentionally a CLI, not a daemon: there is no socket,
HTTP endpoint, account, telemetry, or network dependency.

## Safety model

- `--agent-status` is read-only.
- `--agent-inspect` takes a single read-only pointer and display snapshot; it never clicks, selects, or stores a target.
- `--agent-validate` is a dry run and never posts a mouse event.
- `--agent-run` requires `--confirm`.
- Agent runs always use an explicit fixed screen coordinate (`--x` and `--y`).
- Agent runs require exactly one finite bound: `--clicks` or `--duration`.
- The default agent start delay is one second so a user can cancel or move away.
- Accessibility permission is checked before any event is generated.
- Values are rejected outside the same bounded limits as the native UI.

## Commands

Use the binary inside the app bundle, or replace it with the path from your local
build:

```sh
APP=/Applications/SymClick.app/Contents/MacOS/SymClick
$APP --agent-help
$APP --agent-status
$APP --agent-inspect
$APP --agent-validate --x 640 --y 420 --clicks 25 --cps 100
$APP --agent-run --confirm --x 640 --y 420 --clicks 25 --cps 100 --delay 1
```

The `--agent-help` response is the versioned protocol contract. Agents should
check the `protocol` field and refuse unknown major versions.

## JSONL events

Every output line is one JSON object. A successful validation looks like:

```json
{"protocol":"symclick-agent/v1","event":"validated","valid":true,"target":{"x":640,"y":420},"cps":100,"button":"left","pattern":"single","jitter":0,"start_delay_seconds":1,"bound":{"type":"clicks","value":25}}
```

A real run emits `ready`, `started`, and `completed` events. The final event
contains the logical click count and either `click-limit` or `duration-limit` as
the reason. Errors use `event: "error"` and a stable `code`, including:

- `invalid_request` — missing, malformed, or out-of-bounds arguments.
- `accessibility_required` — macOS permission is not enabled for SymClick.

Exit status is `0` for a completed command, `2` for invalid input, and `3` when
Accessibility permission is required. A caller should not retry an invalid
request without changing it.

The checked-in examples in `tests/fixtures/agent-v1/` cover status, both bound
types, both completion reasons, and the documented errors. Run `make agent-check`
to validate these fixtures and compare the read-only CLI output. Run and permission
error fixtures are examples only: the test never starts a real run or changes
Accessibility permission. Status fields such as architecture and permission
depend on the host.

The opt-in `--agent-inspect` command returns an `inspection` event with the
current `pointer`, active `displays`, their global `bounds`, and each display’s
backing `scale` (or `null` if unavailable). Coordinates and bounds are Core
Graphics global points, not physical pixels; the origin is the upper-left of the
main display and secondary displays can have negative coordinates. The snapshot
is instantaneous and may become stale if the pointer or displays move. The
command captures no screenshot and writes no persistent data. A nonzero exit
with `display_unavailable` or `pointer_unavailable` means no snapshot was made.
Extra arguments are rejected.

## Recommended AI-agent flow

1. Run `--agent-status` and inspect `accessibility` and `protocol`.
2. Ask the user to move the pointer to the intended target, then invoke the
   optional `--agent-inspect` once. Show the returned coordinate and ask the
   user to explicitly confirm that exact target; inspection does not select or
   authorize it. Do not infer a target from a screenshot.
3. Build a finite plan with a click count or duration, conservative CPS, and a
   start delay.
4. Run `--agent-validate` and show the normalized plan to the user.
5. Require an explicit confirmation before invoking `--agent-run`.
6. Stream and display the JSONL events. Treat a missing `completed` event as an
   interrupted or failed run, not as success.
7. Never use the agent CLI for an unlimited run, stealth behavior, anti-cheat
   evasion, or a target the user did not authorize.

## Coordinate and timing notes

Coordinates use the same global screen space as Core Graphics. Secondary
displays can have negative coordinates. The engine schedules logical clicks with
a monotonic clock; actual throughput still depends on macOS and the target app.
Double-click mode emits one logical run with two click-state pairs, while the
reported count remains the number of logical clicks requested.

This protocol is designed to be predictable and inspectable, not to hide
automation from a game or service. The target application and its rules always
take precedence.

## Machine-readable schema and compatibility

[`schemas/symclick-agent-v1.schema.json`](../schemas/symclick-agent-v1.schema.json)
is a JSON Schema draft 2020-12 schema for **one JSONL event**. The `validated`
and `ready` variants describe normalized plans, including their finite bound.
Validate each event separately; the pretty-printed `--agent-help` response is a
separate JSON document, not a JSONL event. A schema cannot verify event ordering,
exit status, user confirmation, or whether an actual run completed.

Within v1, new optional fields may be added to existing events. Consumers should
ignore fields they do not recognize. Removing or changing the meaning or type of
existing fields, changing required fields, adding event types or enum values, or
changing safety bounds requires a new protocol major version. Consumers should
reject unknown protocol versions and handle unknown events as unsupported rather
than treating them as success. The schema permits extra fields for forward
compatibility but deliberately restricts event names and existing enum values.

To check the schema, documentation examples, and live safe command output, install
`jsonschema` in a development-only Python environment and run
`python tests/test_agent_schema.py`. This is not a native app dependency and the
test never invokes `--agent-run`.
