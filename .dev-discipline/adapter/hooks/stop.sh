#!/bin/bash
# stop.sh — Claude Code Stop adapter for dev-discipline.
# Translates dev-discipline-run.sh output to Claude Code Stop JSON format.
# Stop hook uses {"decision":"block","reason":"..."} not hookSpecificOutput.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/dev-discipline-run.sh" stop 2>/dev/null) || true

_dd_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

case "$RESULT" in
  BLOCK:*)
    reason=$(_dd_escape "${RESULT#BLOCK:}")
    printf '{"decision":"block","reason":"%s"}' "$reason"
    ;;
  WARN:*)
    # Stop WARN -> stderr only (non-blocking nudge)
    printf '%s\n' "${RESULT#WARN:}" >&2
    ;;
esac
exit 0
