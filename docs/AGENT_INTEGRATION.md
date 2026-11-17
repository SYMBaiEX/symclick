# SymClick local agent integration

SymClick v1.3 introduces a small local command contract for AI agents and other
automation clients. It is intentionally a CLI, not a daemon: there is no socket,
HTTP endpoint, account, telemetry, or network dependency.

## Safety model

- `--agent-status` is read-only.
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

## Recommended AI-agent flow

1. Run `--agent-status` and inspect `accessibility` and `protocol`.
2. Ask the user to identify or confirm the target coordinate; do not infer a
   target from a screenshot without user confirmation.
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
