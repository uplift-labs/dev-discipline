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

With Codex hook integration:

```bash
curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | DD_WITH_CODEX=1 bash
```

Codex support installs project-local hooks in `.codex/hooks.json`, enables `features.codex_hooks = true` in `.codex/config.toml`, and adds dev-discipline guidance to `AGENTS.md`. Codex only loads project-local `.codex/` configuration for trusted projects.

## Guards

### commit-checks
Validates conventional commit format (`type(scope): description`) and warns when committing code without test files.

### regression-guard
**Nudge mode** (default): Warns before `git push` / `git merge main` to run the full test suite. Auto-detects your test runner and suggests the command.

**Gate mode** (opt-in): Create `.uplift/dev-discipline/test-cmd` with your test command. The guard will run it and block push/merge if tests fail.

```bash
echo "npm test" > .uplift/dev-discipline/test-cmd
```

### rare-commits-reminder
Blocks edits when uncommitted changes exceed thresholds (default: 5 files or 100 insertions). At session end, blocks on severe overflow (3x thresholds) to prevent work loss.

### tdd-order-tracker
Tracks whether tests are written before code in each session. Soft nudge by default; enable TDD mode for hard blocking:

```bash
# Option 1: config file
echo "TDD_MODE=1" >> .uplift/dev-discipline/config

# Option 2: marker file
mkdir -p .dev-discipline
touch .dev-discipline/.tdd-mode

# Option 3: environment variable
export DEV_DISCIPLINE_TDD_MODE=1
```

### dead-branch-guard
Warns or blocks when switching branches (`git checkout`, `git switch`) with uncommitted changes. Git silently carries uncommitted changes to the target branch — this guard prevents accidental cross-branch contamination. Blocks on protected branches (main/master), warns on others.

### force-push-guard
Blocks `git push --force` to protected branches (main/master). Asks for confirmation on force push to feature branches. Allows `--force-with-lease` to non-protected branches without interference.

### main-branch-commit-guard
Warns when committing directly to a protected branch (main/master). Encourages feature branch + PR workflow. Allows merge commits and `--allow-empty` commits.

### todo-debt-tracker
Counts net new `TODO`/`FIXME`/`HACK`/`XXX` markers in uncommitted changes at session end. Warns when new markers appear; asks for confirmation when count exceeds threshold (default: 5).

## Agent integrations

### Claude Code

Claude Code integration uses `PreToolUse` hooks for Bash/Edit/Write and a `Stop` hook for session-end checks. `BLOCK`, `ASK`, and `WARN` map to Claude Code's hook response format.

### Codex

Codex integration uses `PreToolUse` hooks for `Bash` and `apply_patch` plus a `Stop` hook. `BLOCK` maps to a Codex deny decision. `WARN` maps to `systemMessage`. Codex `PreToolUse` does not currently support interactive `ask`, so `ASK` maps to deny by default. To make `ASK` non-blocking in Codex, set:

```bash
export DEV_DISCIPLINE_CODEX_ASK_BEHAVIOR=warn
```

Codex edit tracking is based on file paths extracted from `apply_patch` payloads. Shell commands that modify files directly are still covered by Bash guards, but they do not provide per-file edit paths for `tdd-order-tracker`.

## Configuration

Edit `.uplift/dev-discipline/config`:

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
bash tests/test-adapter-codex.sh
bash tests/test-json-merge.sh
```

## Requirements

- bash 4+
- git
- Guard runtime has no other dependencies
- Hook integration merge helpers use python3 during install/uninstall

## License

MIT
