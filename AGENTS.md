# AGENTS.md

## Project

dev-discipline is a pure bash guard suite for AI coding agents. It enforces development hygiene: conventional commits, test-before-push, TDD edit order, rare-commit reminders, branch-switch warnings, force-push protection, protected-branch commit warnings, and TODO debt tracking.

The core is agent-independent. Claude Code and Codex support live in adapter layers.

## Commands

```bash
bash tests/run.sh
bash tests/test-adapter-codex.sh
bash tests/test-json-merge.sh
```

Run the relevant single guard with:

```bash
bash tests/run.sh commit-checks
bash tests/run.sh regression-guard
bash tests/run.sh rare-commits-reminder
bash tests/run.sh tdd-order-tracker
```

There is no build step, linter, or package manager. Requirements are bash 4+, git, and python3 for installer merge helpers/tests.

## Architecture

```text
Agent Hook Event
  -> adapter/hooks/*.sh or adapter/codex/hooks/*.sh
    -> core/cmd/dev-discipline-run.sh <group>
      -> core/guards/{guard-name}.sh
    <- BLOCK:|ASK:|WARN:|empty
  <- Agent-specific JSON
```

`core/cmd/dev-discipline-run.sh` owns guard ordering and priority: `BLOCK` short-circuits, then first `ASK`, then concatenated `WARN`, then pass.

## Conventions

- Keep guard logic in `core/guards/` agent-agnostic.
- Keep Claude-specific behavior in `adapter/hooks/`.
- Keep Codex-specific behavior in `adapter/codex/hooks/`.
- Guards read JSON from stdin and signal only through stdout prefixes.
- All guard scripts must fail open and exit 0.
- Use `#!/bin/bash`, not `#!/bin/sh`.
- Preserve Windows/MSYS compatibility: prefer `[[:space:]]` over `\s`.

## Codex Notes

Codex hooks require `features.codex_hooks = true`. Project-local `.codex/` config loads only for trusted projects.

Codex `PreToolUse` supports deny/block and `systemMessage`, but not interactive `ask`. The Codex adapter maps `ASK:` to deny by default. `DEV_DISCIPLINE_CODEX_ASK_BEHAVIOR=warn` makes it non-blocking.
