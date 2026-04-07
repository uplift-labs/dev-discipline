#!/bin/bash
# rare-commits-reminder.sh — Dev Discipline Guard
# Blocks edits when session has many uncommitted changes.
# At Stop time: mild overflow -> WARN, severe (3x) -> BLOCK.
#
# Input: JSON on stdin (hook payload)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"
. "$(dirname "$0")/../lib/config.sh"

HOOK_EVENT=$(json_field "hook_event_name" "$INPUT")

# Whitelist check for PreToolUse — skip auto-generated files
if [ "$HOOK_EVENT" != "Stop" ]; then
  FILE=$(json_field "file_path" "$INPUT")
  FILE=$(printf '%s' "$FILE" | tr '\\' '/')

  # Apply whitelist patterns from config
  if [ -n "${WHITELIST_PATTERNS:-}" ]; then
    IFS=',' read -ra _patterns <<< "$WHITELIST_PATTERNS"
    for _pat in "${_patterns[@]}"; do
      _pat=$(printf '%s' "$_pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      case "$FILE" in
        *${_pat}*) exit 0 ;;
      esac
    done
  fi
fi

# Thresholds from config
MAX_FILES="${RARE_COMMITS_MAX_FILES:-5}"
MAX_INS="${RARE_COMMITS_MAX_INSERTIONS:-100}"
SEVERE_FILES=$((MAX_FILES * 3))
SEVERE_INS=$((MAX_INS * 3))

# Count uncommitted changes (staged + unstaged + untracked)
CHANGED=$(git diff --stat HEAD 2>/dev/null | tail -1)
STAGED=$(git diff --cached --stat 2>/dev/null | tail -1)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

# Parse file counts from diff --stat summary line
changed_files() {
  printf '%s' "$1" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0
}
insertions() {
  printf '%s' "$1" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0
}

DIFF_FILES=$(changed_files "$CHANGED")
STAGED_FILES=$(changed_files "$STAGED")
DIFF_INS=$(insertions "$CHANGED")
STAGED_INS=$(insertions "$STAGED")

TOTAL_FILES=$((DIFF_FILES + STAGED_FILES + UNTRACKED))
TOTAL_INS=$((DIFF_INS + STAGED_INS))

if [ "$TOTAL_FILES" -gt "$MAX_FILES" ] || [ "$TOTAL_INS" -gt "$MAX_INS" ]; then
  LAST_COMMIT=$(git log -1 --format='%ar' 2>/dev/null || echo "unknown")

  if [ "$HOOK_EVENT" = "Stop" ]; then
    if [ "$TOTAL_FILES" -gt "$SEVERE_FILES" ] || [ "$TOTAL_INS" -gt "$SEVERE_INS" ]; then
      printf 'BLOCK:[dev-discipline:rare-commits] STOP BLOCKED: %d uncommitted files (~%d insertions). Last commit: %s. Commit your work NOW before the session ends.' "$TOTAL_FILES" "$TOTAL_INS" "$LAST_COMMIT"
      exit 0
    fi
    printf 'WARN:[dev-discipline:rare-commits] %d uncommitted files (~%d insertions). Last commit: %s. Consider committing before ending.' "$TOTAL_FILES" "$TOTAL_INS" "$LAST_COMMIT"
    exit 0
  else
    printf 'BLOCK:[dev-discipline:rare-commits] %d uncommitted files (~%d insertions). Last commit: %s. Commit your changes now before continuing.' "$TOTAL_FILES" "$TOTAL_INS" "$LAST_COMMIT"
    exit 0
  fi
fi

exit 0
