#!/bin/bash
# pre-edit.sh — Codex PreToolUse apply_patch adapter for dev-discipline.
# Extracts patch file paths and runs edit/write guards in patch order.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

. "$ROOT/core/lib/json-field.sh"

INPUT=$(cat)
CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0

SESSION_ID=$(json_field "session_id" "$INPUT")

_dd_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

_dd_json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
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

_dd_patch_paths() {
  printf '%s' "$CMD" | awk '
    /^\*\*\* (Add|Update|Delete) File: / {
      sub(/^\*\*\* (Add|Update|Delete) File: /, "")
      print
      next
    }
    /^\*\*\* Move to: / {
      sub(/^\*\*\* Move to: /, "")
      print
      next
    }
  '
}

BEST_ASK=""
BEST_WARN=""

while IFS= read -r FILE_PATH; do
  [ -z "$FILE_PATH" ] && continue

  payload_file=$(_dd_json_escape "$FILE_PATH")
  payload_session=$(_dd_json_escape "${SESSION_ID:-unknown}")
  PAYLOAD=$(printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"apply_patch","file_path":"%s"}' "$payload_session" "$payload_file")

  RESULT=$(printf '%s' "$PAYLOAD" | bash "$ROOT/core/cmd/dev-discipline-run.sh" pre-edit-write 2>/dev/null) || true

  case "$RESULT" in
    BLOCK:*)
      _dd_deny "${RESULT#BLOCK:}"
      exit 0
      ;;
    ASK:*)
      [ -z "$BEST_ASK" ] && BEST_ASK="$RESULT"
      ;;
    WARN:*)
      if [ -z "$BEST_WARN" ]; then
        BEST_WARN="$RESULT"
      else
        BEST_WARN="$BEST_WARN | ${RESULT#WARN:}"
      fi
      ;;
  esac
done <<EOF
$(_dd_patch_paths)
EOF

if [ -n "$BEST_ASK" ]; then
  case "${DEV_DISCIPLINE_CODEX_ASK_BEHAVIOR:-deny}" in
    warn|allow)
      _dd_warn "${BEST_ASK#ASK:}"
      ;;
    *)
      _dd_deny "${BEST_ASK#ASK:}"
      ;;
  esac
elif [ -n "$BEST_WARN" ]; then
  _dd_warn "${BEST_WARN#WARN:}"
fi

exit 0
