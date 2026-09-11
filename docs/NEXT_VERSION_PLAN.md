# SymClick v1.1 product plan

## North star

SymClick should be the fastest safe path from “I need repeated clicks here” to a
completed run. “Best” means instant startup, predictable timing, a stop control that
always wins, and a native app that stays out of the way. It does not mean adding a
cloud account, a heavy UI, or an unbounded mode that can strand a user in a game.

## What was complete before v1.1

- Native AppKit menu-bar app with no Dock icon.
- Global start/stop shortcut, with `⌃⌥C` as the easy default.
- 1–5,000 CPS input, left/right/middle buttons, persistent preferences.
- Dedicated Objective-C++/Core Graphics engine with a responsive stop path.
- Universal arm64/x86_64 build, MIT license, contributor/security docs, CI, and
  signed release packaging.

## v1.1 shipped

- Single or double click patterns, including correct click-state metadata.
- Pointer-following or fixed-location runs, with one-click pointer capture.
- Repeat-until-stopped, click-count, and duration run modes.
- Safe bounds: 1–10,000,000 clicks, 1 second–24 hours, and 0–20 px jitter.
- Optional bounded jitter for repeated-game targets.
- Live count, speed, and limit state in the status item.
- Preferences that expose every setting, plus menu-bar quick controls.
- Settings persistence, input normalization, self-tests, clean universal builds,
  and release documentation.

## User flow

1. Launch SymClick; it appears in the menu bar and registers `⌃⌥C`.
2. Open Preferences once to choose speed, button, pattern, location, and an optional
   run limit. Record a shortcut if the default conflicts with another app.
3. If using a fixed target, place the pointer on it and press **Capture pointer**.
4. Start from the menu or shortcut. The status item shows clicking, CPS, count, and
   the active limit.
5. Stop with the same shortcut/menu item. A count or duration limit stops cleanly.
6. Change settings and start another run; the count resets and the new settings apply.

## Easy wins included in this release

- Live status and click counts make a run observable without opening a window.
- Limits prevent accidental overnight runs while retaining a true repeat mode.
- Fixed targets and capture remove the need to keep the pointer still.
- Double-click and bounded jitter cover more game UI patterns without external code.
- A single Preferences surface and menu shortcuts reduce setup friction.
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

## Release gates

Every release must pass `make clean verify`, confirm both architectures, validate the
bundle signature, test the archive and checksum, pass CI, and have a GitHub release
whose asset hash matches the locally verified archive. Social announcements publish
only after those gates and must link to the exact release asset.
