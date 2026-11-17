# SymClick

[![CI](https://github.com/SYMBaiEX/symclick/actions/workflows/ci.yml/badge.svg)](https://github.com/SYMBaiEX/symclick/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/SYMBaiEX/symclick)](https://github.com/SYMBaiEX/symclick/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

SymClick is a tiny native macOS menu-bar autoclicker. It uses AppKit for the menu,
Carbon for a global start/stop hotkey, and a dedicated Objective-C++/Core Graphics
click engine. There are no third-party dependencies, telemetry, network requests,
or background services. The v1.3 engine adds a local, bounded JSONL agent contract
without making the app harder to stop or exposing a network control surface.

## Features

- Global start/stop shortcut, defaulting to **Control–Option–C** (`⌃⌥C`)
- Shortcut recorder for choosing your own key combination; if macOS rejects one, try another or press Escape to keep the previous shortcut. macOS may reserve shortcuts or other apps may use them, and not every conflict can be detected.
- Configurable speed from 1 to 5,000 clicks per second
- Left, right, and middle mouse buttons
- Single- or double-click patterns
- Follow the pointer or capture a fixed screen location
- Repeat until stopped, stop after a click count (1–10,000,000), or stop after a duration (1 second–24 hours)
- Optional bounded pointer jitter (0–20 pixels)
- Optional 0–10 second start delay so you can move to the target safely
- Live click count and run-limit status in the menu bar
- Reset Defaults action and a diagnostics/smoke-test path for maintainers
- Colorful early-web-inspired Preferences with a mascot and native controls
- Local `--agent-status`, `--agent-inspect`, and `--agent-validate` commands;
  `--agent-run` fails closed pending shared stop controls
- Changes to settings apply while the clicker is running
- Native menu-bar status with no Dock icon
- Universal Apple Silicon and Intel build

## Install

Download the universal macOS archive from [GitHub Releases](https://github.com/SYMBaiEX/symclick/releases/latest),
extract it, and move `SymClick.app` to `/Applications`.

Official distribution releases require Developer ID signing, Apple notarization,
and a stapled ticket. Release checksums are published beside each archive. See
[`docs/RELEASING.md`](docs/RELEASING.md) for the verification procedure.

### Build from source

Requirements: macOS 12 or newer and Xcode Command Line Tools.

```sh
make
open build/SymClick.app
```

Or build and open it in one command:

```sh
make run
```

To copy the built app to `/Applications`:

```sh
make install
```

## First launch

macOS requires Accessibility permission before one app can send mouse events to
another. Start clicking once, approve the prompt, or use **Accessibility Settings…**
in the SymClick menu. If the app does not appear immediately, add
`build/SymClick.app` manually in **System Settings → Privacy & Security →
Accessibility**.

## Usage

1. Open **Preferences…** and choose a shortcut, speed, button, pattern, location, optional run limit, and start delay.
2. For a fixed target, put the pointer over it and choose **Capture pointer**.
3. Press `⌃⌥C` (or choose **Start Clicking**) to begin.
4. Press the same shortcut again to stop, or let the configured click-count/duration limit stop the run.

An optional **Show CLICK! effect** checkbox in Preferences displays a brief,
non-interactive badge near the target during menu-bar runs. It is off by default
and saved locally. Updates are coalesced at most ten times per second, so the
badge is an indicator rather than a display of every click. It is static,
including when Reduce Motion is enabled, and does not appear for agent runs.

The menu exposes the common speed, pattern, location, and run-mode controls so you
can make quick changes without opening Preferences. A new run resets the live count.

The 5,000 CPS setting is intentionally aggressive. Real throughput depends on the
target app and macOS event handling. Start lower, and keep the stop shortcut easy to
reach. Some games and online services prohibit automation; use SymClick only where
it is allowed.

## Local performance report

Run `SymClick.app/Contents/MacOS/SymClick --performance-report` to print a
versioned JSON report for support. It includes the app version, architecture,
Accessibility state, normalized saved speed and run bounds, and timing mode.
The settings describe configuration; `observed_throughput` is `null` because the
report does not run a benchmark or measure clicks. It reads local preferences
and does not send data or post events. Coordinates, usernames, shortcuts, and
secrets are excluded. Review the report before attaching it to an issue.

## Development

```sh
make test
make diagnostics
make smoke
make agent-check
make verify
make package
make clean
```

For visual inspection without changing saved settings or registering a global
shortcut, run `build/SymClick.app/Contents/MacOS/SymClick --preferences-preview`.
Close the preview window to exit.

The release design and deferred roadmap are documented in
[`docs/NEXT_VERSION_PLAN.md`](docs/NEXT_VERSION_PLAN.md).

AI agents and automation clients should start with
[`docs/AGENT_INTEGRATION.md`](docs/AGENT_INTEGRATION.md). The protocol is
local-only and JSONL-based so an agent can inspect and validate a finite
fixed-target plan. `--agent-run` returns `run_unavailable` and does not click
until agent execution can share the visible menu-bar stop controls.

The complete app is implemented in [`src/main.mm`](src/main.mm). The release build
uses `-O3`, link-time optimization, and produces one `.app` bundle. Local builds are
ad-hoc signed by default. Maintainers can pass `SIGN_IDENTITY` to create a hardened,
timestamped Developer ID build.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

For the project-associated token mint and external data links, see
[`docs/TOKEN.md`](docs/TOKEN.md). The app does not require a token or wallet.

## License

SymClick is available under the [MIT License](LICENSE).
