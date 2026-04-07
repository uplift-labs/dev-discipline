# dev-discipline

Development hygiene guards for AI coding agents. Enforces commit discipline, test-before-push, and TDD order — the practices AI assistants most commonly skip.

Part of the [uplift-labs](https://github.com/uplift-labs) trilogy:
- **[safeguard](https://github.com/uplift-labs/safeguard)** — prevent dangerous actions
- **[worktree-sandbox](https://github.com/uplift-labs/worktree-sandbox)** — isolate sessions
- **dev-discipline** — enforce development hygiene

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | bash
```

With Claude Code hook integration:

```bash
curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | DD_WITH_CLAUDE_CODE=1 bash
```

## Guards

### commit-checks
Validates conventional commit format (`type(scope): description`) and warns when committing code without test files.

### regression-guard
**Nudge mode** (default): Warns before `git push` / `git merge main` to run the full test suite. Auto-detects your test runner and suggests the command.

**Gate mode** (opt-in): Create `.dev-discipline/test-cmd` with your test command. The guard will run it and block push/merge if tests fail.

```bash
echo "npm test" > .dev-discipline/test-cmd
```

### rare-commits-reminder
Blocks edits when uncommitted changes exceed thresholds (default: 5 files or 100 insertions). At session end, blocks on severe overflow (3x thresholds) to prevent work loss.

### tdd-order-tracker
Tracks whether tests are written before code in each session. Soft nudge by default; enable TDD mode for hard blocking:

```bash
# Option 1: config file
echo "TDD_MODE=1" >> .dev-discipline/config

# Option 2: marker file
touch .dev-discipline/.tdd-mode

# Option 3: environment variable
export DEV_DISCIPLINE_TDD_MODE=1
```

## Configuration

Edit `.dev-discipline/config`:

```bash
TDD_MODE=0                     # 0=nudge, 1=block
RARE_COMMITS_MAX_FILES=5       # mild threshold
RARE_COMMITS_MAX_INSERTIONS=100
WHITELIST_PATTERNS=             # comma-sep globs to exclude from change counts
```

Environment variables override config values. Prefix: `DEV_DISCIPLINE_`.

## Disable

```bash
# Disable all guards
export DEV_DISCIPLINE_DISABLED=1

# Disable one guard
export DEV_DISCIPLINE_DISABLE_COMMIT_CHECKS=1

# Auto-disabled in CI
# CI=true → all guards are no-ops
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | DD_UNINSTALL=1 bash
```

## Test

```bash
bash tests/run.sh
```

## Requirements

- bash 4+
- git
- No other dependencies

## License

MIT
