# SymClick product plan (v1.3)

## North star

SymClick should be the fastest safe path from “I need repeated clicks here” to a
completed run. “Best” means instant startup, predictable timing, a stop control that
always wins, and a native app that stays out of the way. It does not mean adding a
cloud account, a heavy UI, or an unbounded mode that can strand a user in a game.
For AI agents, “best” also means inspectable state, a dry-run plan, explicit
confirmation, finite bounds, stable machine-readable events, and no hidden control
plane.

## What was complete before v1.1

- Native AppKit menu-bar app with no Dock icon.
- Global start/stop shortcut, with `⌃⌥C` as the easy default.
- 1–5,000 CPS input, left/right/middle buttons, persistent preferences.
- Dedicated Objective-C++/Core Graphics engine with a responsive stop path.
- Universal arm64/x86_64 build, MIT license, contributor/security docs, CI, and
  signed release packaging.

## v1.1 shipped and complete

- Single or double click patterns, including correct click-state metadata.
- Pointer-following or fixed-location runs, with one-click pointer capture.
- Repeat-until-stopped, click-count, and duration run modes.
- Safe bounds: 1–10,000,000 clicks, 1 second–24 hours, and 0–20 px jitter.
- Optional bounded jitter for repeated-game targets.
- Live count, speed, and limit state in the status item.
- Preferences that expose every setting, plus menu-bar quick controls.
- Settings persistence, input normalization, self-tests, clean universal builds,
  and release documentation.

## v1.2 shipped

- Optional 0–10 second start delay: the app visibly arms, then begins clicking; the
  same shortcut cancels the countdown.
- Reset Defaults restores click settings and attempts to restore the default shortcut after confirmation; if macOS rejects it, the previous working shortcut is retained and the user is notified.
- Preferences offer an optional static, coalesced CLICK! indicator for menu-bar runs.
- `--diagnose` reports the bundle version, host architecture, and Accessibility state.
- `--performance-report` adds normalized configuration bounds and timing mode without measuring throughput or exposing coordinates.
- `--smoke-test` boots the real AppKit delegate/menu-bar lifecycle and exits cleanly;
  `make diagnostics` and `make smoke` make these release gates repeatable.

## v1.3 next pass

- `--agent-help` publishes a versioned `symclick-agent/v1` contract.
- `--agent-status` reports version, architecture, Accessibility state, and local
  capabilities without generating input.
- `--agent-inspect` reports a read-only pointer and display snapshot for target confirmation.
- `--agent-validate` normalizes a fixed-target plan without posting any events.
- `--agent-run` fails closed until agent execution can share visible status and
  the menu-bar emergency stop.
- Repository guidance now gives human contributors and coding agents one shared
  safety contract, including how to test without clicking an uncontrolled desktop.

## User flow

1. Launch SymClick; it appears in the menu bar and registers `⌃⌥C`.
2. Open Preferences once to choose speed, button, pattern, location, optional run
   limit, and an optional start delay. Record a shortcut if the default conflicts.
3. If using a start delay, press the shortcut and move to the target while the status
   item says **Starting**; press it again to cancel.
4. Start from the menu or shortcut. The status item shows clicking, CPS, count, and
   the active limit.
5. Stop with the same shortcut/menu item. A count or duration limit stops cleanly.
6. Change settings and start another run; the count resets and the new settings apply.

For an AI-agent flow, use `--agent-status`, ask the user to confirm coordinates,
run `--agent-validate`, show the normalized plan, then have the user start and
stop the run from the menu-bar app. Agent execution remains disabled.

## Easy wins included in this release

- Live status and click counts make a run observable without opening a window.
- Limits prevent accidental overnight runs while retaining a true repeat mode.
- Fixed targets and capture remove the need to keep the pointer still.
- Double-click and bounded jitter cover more game UI patterns without external code.
- A single Preferences surface and menu shortcuts reduce setup friction.
- Start delay and Reset Defaults make recovery and target selection safer.
- Diagnostics and a real lifecycle smoke test turn “it launched” into a repeatable gate.
- Local agent status/validation makes automation inspectable before it can click.
- No telemetry, network calls, npm wrapper, background service, or anti-cheat bypass.

## Removed or deliberately not added

- No npm package: SymClick is a native app, not a JavaScript library or service.
- No unlimited “maximum” mode: 5,000 CPS is the ceiling and every bounded mode has
  a finite, visible maximum.
- No hidden background process, analytics, account, updater, or network dependency.
- No anti-cheat bypass, driver injection, or behavior that claims to make prohibited
  game automation safe.

## Hard wins intentionally deferred

- Notarization is complete for v1.1.0: Apple accepted the archive, the ticket was
  stapled, and `spctl` reports `source=Notarized Developer ID`. Future releases must
  keep the same credentialed submit, staple, and validate gate.
- A Login Item should be opt-in and requires a separate lifecycle/permissions review.
- Per-app targets, profiles, overlays, analytics, and scripted sequences add state and
  permission complexity; they belong behind a measured user need.
- HID/driver-level injection or anti-cheat evasion is out of scope. SymClick uses the
  documented Core Graphics event path and clearly warns that games may prohibit it.
- A richer local IPC protocol, target discovery, screenshot semantics, and resumable
  workflows remain issue-sized work. They should not be added until the v1 JSONL
  contract has real contributor feedback and stronger end-to-end tests.

## Why SymClick is better

Competing autoclickers often trade safety for a giant speed number or hide state in a
window that disappears behind the game. SymClick keeps the controls in the menu bar,
shows whether it is idle, arming, or clicking, makes every limit visible, and keeps a
global stop shortcut easy to reach. The engine is native and dependency-free, while
the local agent contract lets an AI inspect, validate, and confirm a bounded run
without a cloud account or hidden service. The release is signed, notarized, stapled,
and checksum-verifiable. Those are user value; accounts, telemetry, stealth injection,
and elaborate scripting are not.

## Release gates

Every release must pass `make clean verify`, `make diagnostics`, `make smoke`, and
`make agent-check`,
confirm both architectures, validate the bundle signature, test the archive and
checksum, pass CI, and have a GitHub release whose asset hash matches the locally
verified archive. For distribution builds, Apple must return `Accepted`, stapler
validation must pass, and `spctl` must report `source=Notarized Developer ID`.
Social announcements publish only after those gates and must link to the exact release.
