# Changelog

All notable changes to SymClick are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased] (v1.3.0)

### Added

- Optional, off-by-default CLICK! visual indicator for menu-bar runs.

- Local `symclick-agent/v1` JSONL contract for status, dry-run validation, and
  explicitly confirmed finite runs.
- Agent runs require a fixed target, a click-count or duration bound, and a
  preflight Accessibility check; no network listener or background service is added.
- Repository-level `AGENTS.md`, agent integration documentation, and an agent issue form.

### Improved

- `make verify` now checks both universal architectures with the current `lipo`
  command syntax and exercises the agent contract.
- Headless smoke checks report an explicit skip when no interactive display session
  exists instead of aborting or claiming a GUI launch was tested.

## [1.2.0] - 2026-09-13

### Added

- Optional 0–10 second start delay with a clear arming state and cancellation path.
- Reset Defaults action for recovering from a confusing or conflicting configuration.
- `--diagnose` and `--smoke-test` commands plus `make diagnostics`/`make smoke` release checks.

### Improved

- The status item distinguishes an armed countdown from active clicking.
- Maintainer documentation now requires a real launch smoke test before publication.

## [1.1.0] - 2026-09-10

### Added

- Single- and double-click patterns with correct click-state metadata.
- Follow-pointer or fixed-location clicking, with pointer capture.
- Repeat, click-count, and duration run modes with bounded safety limits.
- Optional 0–20 px pointer jitter and live click-count status.
- Expanded Preferences and menu-bar quick controls for every setting.

### Improved

- The click engine keeps the stop path responsive while sustaining aggressive CPS.
- Settings and run state are normalized, persisted, and reflected immediately.
- The universal Developer ID release is notarized and stapled for a clean Gatekeeper launch.
- Release documentation now includes the v1.1 product plan and acceptance gates.

## [1.0.0] - 2026-09-05

### Added

- Native macOS menu-bar interface with no Dock icon.
- Global, user-recordable start/stop shortcut (`⌃⌥C` by default).
- Configurable 1–5,000 clicks-per-second range.
- Left, right, and middle mouse-button modes.
- Live preference updates and persistent settings.
- Universal Apple Silicon and Intel binary.
- Accessibility permission guidance and fail-safe stop behavior.

[1.2.0]: https://github.com/SYMBaiEX/symclick/releases/tag/v1.2.0
[1.1.0]: https://github.com/SYMBaiEX/symclick/releases/tag/v1.1.0
[1.0.0]: https://github.com/SYMBaiEX/symclick/releases/tag/v1.0.0
[Unreleased]: https://github.com/SYMBaiEX/symclick/compare/v1.2.0...HEAD
