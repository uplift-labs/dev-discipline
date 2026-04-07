#!/bin/bash
# commit-checks.sh — Dev Discipline Guard
# Validates conventional commit format and warns on code-without-tests.
#
# Input: JSON on stdin (hook payload with "command" field)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

# Only trigger on git commit commands
CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --- Check 1: Conventional commit format ---

SKIP_CONVENTIONAL=0

# Allow editor-based commits (no -m flag) — can't validate without message
case "$CMD" in
  *" -m "*|*" -m\""*|*" -m'"*|*"-am "*|*"-am\""*|*"-am'"*) ;;
  *) SKIP_CONVENTIONAL=1 ;;
esac

# Allow fixup/squash commits (autosquash)
case "$CMD" in
  *--fixup*|*--squash*) SKIP_CONVENTIONAL=1 ;;
esac

if [ "$SKIP_CONVENTIONAL" -eq 0 ]; then
  # Extract commit message from -m argument
  # Handle: -m "msg", -m 'msg', -am "msg", -m "$(cat <<'EOF'...)"
  CC_MSG=$(printf '%s' "$CMD" | sed -n "s/.*-[a-zA-Z]*m[[:space:]]*\"\([^\"]*\)\".*/\1/p")
  [ -z "$CC_MSG" ] && CC_MSG=$(printf '%s' "$CMD" | sed -n "s/.*-[a-zA-Z]*m[[:space:]]*'\([^']*\)'.*/\1/p")

  # Heredoc pattern: -m "$(cat <<'EOF'\n...\nEOF\n)"
  if [ -z "$CC_MSG" ]; then
    CC_MSG=$(printf '%s' "$CMD" | sed -n 's/.*-[a-zA-Z]*m[[:space:]]*"\$(cat <<.*//p')
  fi

  if [ -n "$CC_MSG" ]; then
    # Strip leading whitespace (heredoc indentation)
    CC_MSG=$(printf '%s' "$CC_MSG" | sed 's/^[[:space:]]*//')

    # For multi-line messages, only validate the first line (title)
    TITLE=$(printf '%s' "$CC_MSG" | head -1)

    # Validate against conventional commits regex
    if ! printf '%s' "$TITLE" | grep -qE '^(feat|fix|chore|docs|style|refactor|perf|test|ci|build|revert)(\(.+\))?(!)?: .+'; then
      printf 'BLOCK:[dev-discipline:commit-checks] Message does not follow conventional commits format. Expected: type(scope)?: description. Types: feat|fix|chore|docs|style|refactor|perf|test|ci|build|revert. Got: %s' "$TITLE"
      exit 0
    fi
  fi
  # Could not extract message — fail open, continue to TDD check
fi

# --- Check 2: TDD gate (code without tests) ---

STAGED=$(git diff --cached --name-only 2>/dev/null)
[ -z "$STAGED" ] && exit 0

HAS_CODE=0
HAS_TEST=0
CODE_FILES=""

for f in $STAGED; do
  base=$(basename "$f")

  # Check if test file
  is_test=0
  case "$f" in
    tests/*|test/*|__tests__/*) is_test=1 ;;
  esac
  case "$base" in
    test_*|test-*|*_test.sh|*_test.py|*_test.go|*_test.rs) is_test=1 ;;
    *.test.ts|*.test.js|*.test.tsx|*.test.jsx) is_test=1 ;;
    *.spec.ts|*.spec.js|*.spec.tsx|*.spec.jsx) is_test=1 ;;
  esac

  if [ "$is_test" -eq 1 ]; then
    HAS_TEST=1
    continue
  fi

  # Check if code file
  case "$base" in
    *.sh|*.py|*.ts|*.js|*.tsx|*.jsx|*.go|*.rs|*.rb|*.java|*.c|*.cpp|*.h|*.cs|*.fs)
      HAS_CODE=1
      CODE_FILES="$CODE_FILES $f"
      ;;
  esac
done

[ "$HAS_CODE" -eq 0 ] && exit 0
[ "$HAS_TEST" -eq 1 ] && exit 0

CODE_LIST=$(printf '%s' "$CODE_FILES" | sed 's/^ //' | tr ' ' ', ')
printf 'WARN:[dev-discipline:commit-checks] Committing code without test files. Code: %s. Consider writing tests for this code.' "$CODE_LIST"
exit 0
