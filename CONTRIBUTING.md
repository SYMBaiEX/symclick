# Contributing to SymClick

Thanks for helping improve SymClick.

The repository-level [`AGENTS.md`](AGENTS.md) is the shared operating contract
for human contributors and coding agents. Read it before touching timing,
Accessibility, packaging, or the agent protocol.

## Before opening a change

- Search existing issues and pull requests to avoid duplicate work.
- Open an issue first for behavioral changes or larger features.
- Keep the app dependency-free unless a dependency has a compelling, documented
  benefit.
- Do not add telemetry, analytics, advertising, or silent network access.
- Keep agent integrations local-only, explicit, finite, and machine-readable.

## Local development

SymClick requires macOS 12 or newer and Xcode Command Line Tools.

```sh
git clone https://github.com/SYMBaiEX/symclick.git
cd symclick
make clean
make verify
```

Use `make run` for a local build. macOS Accessibility permission is required to
manually test click injection. Never run automated click-injection tests against an
uncontrolled desktop session.

`make diagnostics` reports the current bundle version, host architecture, and
Accessibility state. `make smoke` boots the real AppKit/menu-bar lifecycle and exits
automatically when an interactive display session is available; a headless run
reports a deliberate skip. It is safe to run without generating clicks.

For AI-agent work, read [`docs/AGENT_INTEGRATION.md`](docs/AGENT_INTEGRATION.md).
Use `--agent-validate` for dry runs. Never invoke `--agent-run` in tests or a
shared desktop without an explicit user-confirmed target and finite bound.

## Pull requests

- Keep each pull request focused and explain the user-visible behavior.
- Add or update self-tests when changing pure logic.
- Run `make verify` before submitting.
- Verify both starting and stopping through the global hotkey.
- Preserve the emergency-stop path when changing the click engine.
- Keep the JSONL agent protocol backward-compatible within its major version.
- Update `README.md` and `CHANGELOG.md` for user-facing changes.

By contributing, you agree that your contribution is licensed under the MIT License.
