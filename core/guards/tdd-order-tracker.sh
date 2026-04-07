#!/bin/bash
# tdd-order-tracker.sh — Dev Discipline Guard
# Tracks test vs code edit ordering within a session.
# Soft nudge by default, hard block when TDD mode is active.
#
# TDD mode activation (checked in order):
#   1. DEV_DISCIPLINE_TDD_MODE=1 env var
#   2. TDD_MODE=1 in .dev-discipline/config
#   3. .dev-discipline/.tdd-mode marker file exists
#
# Input: JSON on stdin (hook payload with "file_path" field)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"
. "$(dirname "$0")/../lib/config.sh"

# Extract file path
FILE_PATH=$(json_field "file_path" "$INPUT")
[ -z "$FILE_PATH" ] && exit 0

# Normalize path separators
FILE_PATH=$(printf '%s' "$FILE_PATH" | tr '\\' '/')
BASENAME=$(basename "$FILE_PATH")

# Skip non-code files (docs, config, data)
case "$BASENAME" in
  *.md|*.txt|*.json|*.yml|*.yaml|*.toml|*.dat|*.csv|*.lock) exit 0 ;;
  *.gitignore|*.gitattributes|*.editorconfig) exit 0 ;;
  LICENSE|Makefile|Dockerfile|*.dockerfile) exit 0 ;;
esac

# Escape hatch: infrastructure paths always pass
case "$FILE_PATH" in
  */.dev-discipline/*|*/node_modules/*|*/.git/*|*/vendor/*) exit 0 ;;
esac

# Classify: test or code?
IS_TEST=0
case "$FILE_PATH" in
  */tests/*|*/test/*|*/__tests__/*) IS_TEST=1 ;;
esac
case "$BASENAME" in
  test_*|test-*|*_test.sh|*_test.py|*_test.go|*_test.rs) IS_TEST=1 ;;
  *.test.ts|*.test.js|*.test.tsx|*.test.jsx) IS_TEST=1 ;;
  *.spec.ts|*.spec.js|*.spec.tsx|*.spec.jsx) IS_TEST=1 ;;
esac

# Only track recognized code files
IS_CODE=0
case "$BASENAME" in
  *.sh|*.py|*.ts|*.js|*.tsx|*.jsx|*.go|*.rs|*.rb|*.java|*.c|*.cpp|*.h|*.cs|*.fs) IS_CODE=1 ;;
esac

# If neither test nor recognized code, skip
[ "$IS_TEST" -eq 0 ] && [ "$IS_CODE" -eq 0 ] && exit 0

# Session state file
SESSION_ID=$(json_field "session_id" "$INPUT")
STATE_FILE="/tmp/dd-tdd-tracker-${SESSION_ID:-unknown}"

# Record test edits and exit
if [ "$IS_TEST" -eq 1 ]; then
  echo "T:$FILE_PATH" >> "$STATE_FILE"
  exit 0
fi

# It's a code file — check if any tests have been written first
if [ -f "$STATE_FILE" ]; then
  TEST_COUNT=$(grep -c "^T:" "$STATE_FILE" 2>/dev/null); TEST_COUNT=${TEST_COUNT:-0}
  if [ "$TEST_COUNT" -gt 0 ]; then
    echo "C:$FILE_PATH" >> "$STATE_FILE"
    exit 0
  fi
fi

# No tests written yet — check TDD mode
TDD_ACTIVE=0
if [ "${DEV_DISCIPLINE_TDD_MODE:-${TDD_MODE:-0}}" = "1" ]; then
  TDD_ACTIVE=1
fi
if [ "$TDD_ACTIVE" -eq 0 ]; then
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -f "${GIT_ROOT:-.}/.dev-discipline/.tdd-mode" ] && TDD_ACTIVE=1
fi

REL_PATH=$(printf '%s' "$FILE_PATH" | sed 's|.*/\(src/\)|\1|; s|.*/\(lib/\)|\1|; s|.*/\(core/\)|\1|')

if [ "$TDD_ACTIVE" -eq 1 ]; then
  printf 'BLOCK:[dev-discipline:tdd-order] Write tests first. You are editing code (%s) before any tests this session. TDD mode is active — write a failing test, then implement.' "$REL_PATH"
  exit 0
fi

# Soft nudge — record and allow
echo "C:$FILE_PATH" >> "$STATE_FILE"
printf 'WARN:[dev-discipline:tdd-order] You edited code (%s) before writing any tests this session. Consider writing tests first.' "$REL_PATH"
exit 0
