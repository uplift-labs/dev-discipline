# dev-discipline — Contract

## What dev-discipline guarantees

1. **Fail-open.** All guards exit 0. A crashing guard never blocks your workflow.
2. **No external dependencies** beyond bash, git, and standard POSIX utilities.
3. **No network calls.** All logic is local.
4. **No LLM calls.** Fully deterministic — no model inference, no token cost, no unpredictability.
5. **Prefixed output.** Every BLOCK/WARN includes a reason with `[dev-discipline:guard-name]` prefix.
6. **Kill switches work immediately.**
   - `DEV_DISCIPLINE_DISABLED=1` disables all guards.
   - `DEV_DISCIPLINE_DISABLE_<GUARD_NAME>=1` disables individual guards (e.g., `DEV_DISCIPLINE_DISABLE_COMMIT_CHECKS=1`).
   - `CI=true` auto-disables everything (CI environments).
7. **Config is hot-reloadable.** Changes to `.dev-discipline/config` take effect on the next hook invocation. No restart needed.
8. **Installer is idempotent and non-destructive.** Re-running `remote-install.sh` is safe. It never overwrites user config.
9. **Coexistence.** dev-discipline coexists with [safeguard](https://github.com/uplift-labs/safeguard) and [worktree-sandbox](https://github.com/uplift-labs/worktree-sandbox) without conflicts.

## What dev-discipline does NOT guarantee

- **Test suite correctness.** `regression-guard` runs your test command as-is. If your tests are flaky, the guard will block on flakes.
- **Complete commit message validation.** `commit-checks` validates the title line format only. It does not enforce body content, line length, or semantic accuracy.
- **TDD enforcement.** `tdd-order-tracker` tracks edit order, not test quality. Writing an empty test file satisfies the guard.
- **Coverage.** No guard checks test coverage metrics. Coverage enforcement is out of scope.

## Guards included

| Guard | Hook | What it does |
|---|---|---|
| `commit-checks` | PreToolUse Bash | Validates conventional commit format; warns on code without tests |
| `regression-guard` | PreToolUse Bash | Nudges to run tests before push/merge; blocks on failure if `test-cmd` configured |
| `rare-commits-reminder` | PreToolUse Edit/Write + Stop | Blocks when too many uncommitted changes accumulate |
| `tdd-order-tracker` | PreToolUse Edit/Write | Nudges (or blocks in TDD mode) when code is edited before tests |
