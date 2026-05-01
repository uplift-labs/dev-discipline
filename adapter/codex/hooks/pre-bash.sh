#!/bin/bash
# pre-bash.sh — Codex PreToolUse Bash adapter for dev-discipline.
# Translates dev-discipline-run.sh output to Codex hook JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/dev-discipline-run.sh" pre-bash 2>/dev/null) || true

_dd_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

_dd_deny() {
  local reason
  reason=$(_dd_escape "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
}

_dd_warn() {
  local message
  message=$(_dd_escape "$1")
  printf '{"systemMessage":"%s"}' "$message"
}

case "$RESULT" in
  BLOCK:*)
    _dd_deny "${RESULT#BLOCK:}"
    ;;
  ASK:*)
    case "${DEV_DISCIPLINE_CODEX_ASK_BEHAVIOR:-deny}" in
      warn|allow)
        _dd_warn "${RESULT#ASK:}"
        ;;
      *)
        _dd_deny "${RESULT#ASK:}"
        ;;
    esac
    ;;
  WARN:*)
    _dd_warn "${RESULT#WARN:}"
    ;;
esac
exit 0
