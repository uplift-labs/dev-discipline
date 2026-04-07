# Changelog

## 1.0.0 — 2026-04-08

First stable release. 8 guards, zero dependencies, fail-open by design.

### Guards

- **commit-checks** — conventional commit format validation, test-file co-commit nudge
- **regression-guard** — nudge/gate before `git push` and `git merge main`
- **rare-commits-reminder** — blocks edits when uncommitted changes exceed thresholds
- **tdd-order-tracker** — tracks test-before-code discipline, optional TDD hard mode
- **dead-branch-guard** — prevents branch switching with uncommitted changes
- **force-push-guard** — blocks `git push --force` to protected branches
- **main-branch-commit-guard** — warns on direct commits to main/master
- **todo-debt-tracker** — tracks net new TODO/FIXME markers per session

### Infrastructure

- Multiplexer with priority dispatch (BLOCK > ASK > WARN > pass)
- Adapter layer for Claude Code hook integration
- Configuration layering: defaults, config file, env vars, per-guard disable
- Fixture-driven test suite (37 tests)
- One-line remote installer with uninstall support
