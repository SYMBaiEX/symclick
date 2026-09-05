# SymClick

[![CI](https://github.com/SYMBaiEX/symclick/actions/workflows/ci.yml/badge.svg)](https://github.com/SYMBaiEX/symclick/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/SYMBaiEX/symclick)](https://github.com/SYMBaiEX/symclick/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

SymClick is a tiny native macOS menu-bar autoclicker. It uses AppKit for the menu,
Carbon for a global start/stop hotkey, and a dedicated Objective-C++/Core Graphics
click engine. There are no third-party dependencies, telemetry, network requests,
or background services.

## Features

- Global start/stop shortcut, defaulting to **Control–Option–C** (`⌃⌥C`)
- Shortcut recorder for choosing your own key combination
- Configurable speed from 1 to 5,000 clicks per second
- Left, right, and middle mouse buttons
- Changes to speed and mouse button apply while the clicker is running
- Native menu-bar status with no Dock icon
- Universal Apple Silicon and Intel build

## Install

Download the universal macOS archive from [GitHub Releases](https://github.com/SYMBaiEX/symclick/releases/latest),
extract it, and move `SymClick.app` to `/Applications`.

The v1.0.0 binary is Developer ID–signed with hardened runtime but is not notarized.
On first launch, macOS may ask you to confirm it in **System Settings → Privacy &
Security → Open Anyway**. Release checksums are published beside each archive.

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

1. Put the pointer over the target.
2. Press `⌃⌥C` to start.
3. Press `⌃⌥C` again to stop.
4. Use **Preferences…** to record another shortcut or enter an exact speed.

The 5,000 CPS setting is intentionally aggressive. Real throughput depends on the
target app and macOS event handling. Start lower, and keep the stop shortcut easy to
reach. Some games and online services prohibit automation; use SymClick only where
it is allowed.

## Development

```sh
make test
make verify
make package
make clean
```

The complete app is implemented in [`src/main.mm`](src/main.mm). The release build
uses `-O3`, link-time optimization, and produces one `.app` bundle. Local builds are
ad-hoc signed by default. Maintainers can pass `SIGN_IDENTITY` to create a hardened,
timestamped Developer ID build.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

SymClick is available under the [MIT License](LICENSE).
