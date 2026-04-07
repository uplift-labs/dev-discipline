# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

dev-discipline — development hygiene guards for AI coding agents. Enforces commit discipline, test-before-push, TDD order, and conventional commits via Claude Code hooks. Pure bash, no external dependencies, no network/LLM calls, fail-open by design.

Part of the uplift-labs trilogy: safeguard (dangerous actions), worktree-sandbox (session isolation), dev-discipline (hygiene).

## Commands

```bash
# Run all tests
bash tests/run.sh

# Run tests for a single guard
bash tests/run.sh commit-checks
bash tests/run.sh regression-guard
bash tests/run.sh rare-commits-reminder
bash tests/run.sh tdd-order-tracker
```

No build step, no linter, no package manager. Requirements: bash 4+, git.

## Architecture

### Guard dispatch flow

```
Claude Code Hook Event
  -> adapter/hooks/{pre-bash,pre-edit,stop}.sh    # translates hook JSON to stdin
    -> core/cmd/dev-discipline-run.sh <group>      # multiplexer: dispatches to guards
      -> core/guards/{guard-name}.sh               # individual guard logic
    <- BLOCK:|ASK:|WARN:|empty                     # guard verdict (prefix-based)
  <- Claude Code JSON                              # adapter converts back
```

### Multiplexer groups (dev-discipline-run.sh)

| Group | Guards dispatched |
|---|---|
| `pre-bash` | commit-checks, regression-guard, dead-branch-guard, force-push-guard, main-branch-commit-guard |
| `pre-edit-write` | rare-commits-reminder, tdd-order-tracker |
| `stop` | rare-commits-reminder, todo-debt-tracker |

Priority: BLOCK (short-circuits) > ASK > WARN > pass. Multiple WARNs are concatenated with ` | `.

### Output protocol

Guards communicate exclusively via stdout prefix strings:
- `BLOCK:<reason>` — deny the action
- `ASK:<reason>` — prompt user for confirmation
- `WARN:<context>` — informational, non-blocking
- empty — allow

All guards exit 0 always (fail-open). Exit code is never used for signaling.

### Adapters (adapter/hooks/)

Convert between Claude Code hook JSON format and the internal prefix protocol. Three adapters map to three hook events: `pre-bash.sh` (PreToolUse Bash), `pre-edit.sh` (PreToolUse Edit|Write), `stop.sh` (Stop).

### Configuration layering

1. Hardcoded defaults in guards
2. `.dev-discipline/config` (shell-sourceable key=value)
3. Environment variables (`DEV_DISCIPLINE_` prefix overrides config)
4. Per-guard disable: `DEV_DISCIPLINE_DISABLE_COMMIT_CHECKS=1` (dashes to underscores, uppercased)

Config is hot-reloadable (re-read every hook invocation).

### Utility libraries (core/lib/)

- `config.sh` — locates git root, sources `.dev-discipline/config`, applies env overrides
- `json-field.sh` — lightweight JSON field extraction without external deps (`json_field` for simple values, `json_field_long` for escaped strings)

## Test system

Fixture-driven. Each fixture is a JSON file simulating a hook payload.

- `tp-*.json` — "true positive", expect the guard to trigger (BLOCK/ASK/WARN)
- `tn-*.json` — "true negative", expect the guard to pass (empty output)

Test harness (`tests/run.sh`) creates a temp git repo per fixture, sets up guard-specific state (staged files, config, etc.), runs the guard, and validates output.

37 fixtures total across 8 guards. When adding a new guard: add at least 1 tp and 1 tn fixture.

## Key conventions

- All scripts use `#!/bin/bash` (not `#!/bin/sh` — required for Windows/MSYS compatibility).
- `set -u` everywhere (undefined variable = immediate error).
- Guards read JSON from stdin, never from files or arguments.
- Conventional commit format enforced: `type(scope): description` where type is one of: feat, fix, chore, docs, style, refactor, perf, test, ci, build, revert.
- Windows/MSYS: use `[[:space:]]` not `\s`, avoid `timeout` command, avoid non-ASCII in curl JSON payloads.
