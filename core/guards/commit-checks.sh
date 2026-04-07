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

# --- Check 2: Secret leak detection (before TDD gate — secrets are critical) ---

. "$(dirname "$0")/../lib/config.sh"
: "${SECRET_SCAN_ENABLED:=1}"

STAGED=$(git diff --cached --name-only 2>/dev/null)
[ -z "$STAGED" ] && exit 0

if [ "$SECRET_SCAN_ENABLED" = "1" ]; then
  : "${SECRET_SCAN_SKIP_PATHS:=tests/,fixtures/,__mocks__/}"

  # Get staged diff (added lines only), capped for performance
  SDIFF=$(git diff --cached -U0 2>/dev/null | head -3000)

  if [ -n "$SDIFF" ]; then
    # Filter out skipped paths: extract current file from diff headers, skip hunks in excluded paths
    _skip_file=0
    ADDED_LINES=""
    while IFS= read -r _line; do
      case "$_line" in
        "diff --git "*)
          _skip_file=0
          _diff_path=$(printf '%s' "$_line" | sed 's|.*b/||')
          IFS=',' read -ra _skip_pats <<< "$SECRET_SCAN_SKIP_PATHS"
          for _sp in "${_skip_pats[@]}"; do
            _sp=$(printf '%s' "$_sp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$_diff_path" in
              ${_sp}*) _skip_file=1 ;;
            esac
          done
          continue
          ;;
        +++*) continue ;;
        +*)
          [ "$_skip_file" -eq 1 ] && continue
          ADDED_LINES="${ADDED_LINES}${_line}
"
          ;;
      esac
    done <<< "$SDIFF"

    if [ -n "$ADDED_LINES" ]; then
      # Scan for secret patterns
      SECRET_TYPE=""
      if printf '%s' "$ADDED_LINES" | grep -qE 'AKIA[A-Z0-9]{16}'; then
        SECRET_TYPE="AWS Access Key ID"
      elif printf '%s' "$ADDED_LINES" | grep -qE 'ghp_[a-zA-Z0-9]{36}'; then
        SECRET_TYPE="GitHub Personal Access Token"
      elif printf '%s' "$ADDED_LINES" | grep -qE 'gho_[a-zA-Z0-9]{36}'; then
        SECRET_TYPE="GitHub OAuth Token"
      elif printf '%s' "$ADDED_LINES" | grep -qE 'glpat-[a-zA-Z0-9_-]{20,}'; then
        SECRET_TYPE="GitLab Personal Access Token"
      elif printf '%s' "$ADDED_LINES" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then
        SECRET_TYPE="Secret Key (generic)"
      elif printf '%s' "$ADDED_LINES" | grep -qE '\-\-\-\-\-BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY\-\-\-\-\-'; then
        SECRET_TYPE="Private Key"
      fi

      if [ -n "$SECRET_TYPE" ]; then
        printf 'BLOCK:[dev-discipline:commit-checks] Potential secret detected in staged changes. Pattern: %s. Remove the secret and use environment variables instead.' "$SECRET_TYPE"
        exit 0
      fi
    fi
  fi
fi

# --- Check 3: TDD gate (code without tests) ---

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

if [ "$HAS_CODE" -eq 1 ] && [ "$HAS_TEST" -eq 0 ]; then
  CODE_LIST=$(printf '%s' "$CODE_FILES" | sed 's/^ //' | tr ' ' ', ')
  printf 'WARN:[dev-discipline:commit-checks] Committing code without test files. Code: %s. Consider writing tests for this code.' "$CODE_LIST"
fi

exit 0
