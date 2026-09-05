# Contributing to SymClick

Thanks for helping improve SymClick.

## Before opening a change

- Search existing issues and pull requests to avoid duplicate work.
- Open an issue first for behavioral changes or larger features.
- Keep the app dependency-free unless a dependency has a compelling, documented
  benefit.
- Do not add telemetry, analytics, advertising, or silent network access.

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

## Pull requests

- Keep each pull request focused and explain the user-visible behavior.
- Add or update self-tests when changing pure logic.
- Run `make verify` before submitting.
- Verify both starting and stopping through the global hotkey.
- Preserve the emergency-stop path when changing the click engine.
- Update `README.md` and `CHANGELOG.md` for user-facing changes.

By contributing, you agree that your contribution is licensed under the MIT License.
