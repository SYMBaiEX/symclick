# Security Policy

## Supported versions

Security updates are provided for the latest release of SymClick.

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/SYMBaiEX/symclick/security/advisories/new)
and include reproduction steps, affected versions, and expected impact.

You should receive an acknowledgement within seven days. Confirmed issues will be
coordinated privately until a fix and disclosure timeline are ready.

## Security boundaries

SymClick requires macOS Accessibility permission to generate mouse events. It does
not request administrator privileges, send network requests, collect analytics, or
install a privileged helper. Its preferences are stored through `NSUserDefaults`.

Only download releases from the official GitHub repository. Each binary archive is
accompanied by a SHA-256 checksum.

The local agent protocol is intentionally narrow: it has no network listener,
requires explicit confirmation for real runs, requires a fixed target and finite
bound, and checks Accessibility before posting events. Do not widen it into a
remote control plane or add a mode intended to evade game or service rules.

The release process also requires Apple notarization and stapling. A valid release
must pass `xcrun stapler validate` and report `source=Notarized Developer ID` from
`spctl`; a Developer ID signature alone is not treated as sufficient.
