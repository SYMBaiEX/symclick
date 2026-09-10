# Changelog

All notable changes to SymClick are documented here. This project follows
[Semantic Versioning](https://semver.org/).

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

[1.1.0]: https://github.com/SYMBaiEX/symclick/releases/tag/v1.1.0
[1.0.0]: https://github.com/SYMBaiEX/symclick/releases/tag/v1.0.0
