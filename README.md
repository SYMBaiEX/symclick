# TurboClick

TurboClick is a tiny native macOS menu-bar autoclicker. It uses AppKit for the menu,
Carbon for a global start/stop hotkey, and a dedicated Objective-C++/Core Graphics
click engine. There are no third-party dependencies or background services.

## Features

- Global start/stop shortcut, defaulting to **Control–Option–C** (`⌃⌥C`)
- Shortcut recorder for choosing your own key combination
- Configurable speed from 1 to 5,000 clicks per second
- Left, right, and middle mouse buttons
- Changes to speed and mouse button apply while the clicker is running
- Native menu-bar status with no Dock icon
- Universal Apple Silicon and Intel build

## Build and run

Requirements: macOS 12 or newer and Xcode Command Line Tools.

```sh
make
open build/TurboClick.app
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
in the TurboClick menu. If the app does not appear immediately, add
`build/TurboClick.app` manually in **System Settings → Privacy & Security →
Accessibility**.

## Usage

1. Put the pointer over the target.
2. Press `⌃⌥C` to start.
3. Press `⌃⌥C` again to stop.
4. Use **Preferences…** to record another shortcut or enter an exact speed.

The 5,000 CPS setting is intentionally aggressive. Real throughput depends on the
target app and macOS event handling. Start lower, and keep the stop shortcut easy to
reach. Some games and online services prohibit automation; use TurboClick only where
it is allowed.

## Development

```sh
make test
make clean
```

The complete app is implemented in [`src/main.mm`](src/main.mm). The release build
uses `-O3`, link-time optimization, and produces one ad-hoc-signed `.app` bundle.

