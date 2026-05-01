#!/bin/bash
# stop.sh — Codex Stop adapter for dev-discipline.
# Stop block decisions make Codex continue with the supplied reason.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/dev-discipline-run.sh" stop 2>/dev/null) || true

_dd_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

case "$RESULT" in
  BLOCK:*)
    reason=$(_dd_escape "${RESULT#BLOCK:}")
    printf '{"decision":"block","reason":"%s"}' "$reason"
    ;;
  ASK:*)
    reason=$(_dd_escape "${RESULT#ASK:}")
    printf '{"decision":"block","reason":"%s"}' "$reason"
    ;;
  WARN:*)
    message=$(_dd_escape "${RESULT#WARN:}")
    printf '{"systemMessage":"%s"}' "$message"
    ;;
esac
exit 0
