#!/bin/bash
# regression-guard.sh — Dev Discipline Guard
# Nudges or gates push/merge to main based on test suite status.
#
# Two modes:
#   Default (nudge): Warns to run tests before pushing. Suggests test command
#     if auto-detected.
#   Opt-in (gate): If .dev-discipline/test-cmd exists, runs the configured
#     command and blocks on failure.
#
# Input: JSON on stdin (hook payload with "command" field)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

# Trigger on git push OR git merge into main/master
CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0
case "$CMD" in
  *git\ push*) ;;
  *git\ merge*main*|*git\ merge*master*) ;;
  *) exit 0 ;;
esac

# Locate project root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
TEST_CMD_FILE="$GIT_ROOT/.dev-discipline/test-cmd"

# --- Opt-in mode: .dev-discipline/test-cmd exists ---
if [ -f "$TEST_CMD_FILE" ]; then
  TEST_CMD=$(head -1 "$TEST_CMD_FILE" 2>/dev/null)
  [ -z "$TEST_CMD" ] && exit 0

  OUTPUT=$(eval "$TEST_CMD" 2>&1)
  EXIT_CODE=$?

  # pytest exit 5 = no tests collected (not a failure)
  if printf '%s' "$TEST_CMD" | grep -qiE 'pytest|py\.test'; then
    [ "$EXIT_CODE" -eq 5 ] && exit 0
  fi

  [ "$EXIT_CODE" -eq 0 ] && exit 0

  # Tests failed — block
  TAIL=$(printf '%s' "$OUTPUT" | tail -20)
  TAIL_ESCAPED=$(printf '%s' "$TAIL" | tr '\n' ';' | sed 's/"/\\"/g')
  printf 'BLOCK:[dev-discipline:regression-guard] Tests FAILING — fix before pushing. Output: %s' "$TAIL_ESCAPED"
  exit 0
fi

# --- Default mode: nudge ---

# Auto-detect test runner to suggest command
SUGGEST=""
if [ -f "$GIT_ROOT/Cargo.toml" ]; then
  SUGGEST="cargo test"
elif [ -f "$GIT_ROOT/go.mod" ]; then
  SUGGEST="go test ./..."
elif [ -f "$GIT_ROOT/pyproject.toml" ] || [ -f "$GIT_ROOT/pytest.ini" ] || [ -f "$GIT_ROOT/setup.cfg" ]; then
  SUGGEST="pytest"
elif [ -f "$GIT_ROOT/package.json" ]; then
  if grep -q '"test"' "$GIT_ROOT/package.json" 2>/dev/null; then
    if ! grep -q 'no test specified' "$GIT_ROOT/package.json" 2>/dev/null; then
      SUGGEST="npm test"
    fi
  fi
elif [ -f "$GIT_ROOT/Makefile" ]; then
  if grep -q '^test:' "$GIT_ROOT/Makefile" 2>/dev/null; then
    SUGGEST="make test"
  fi
fi

# Check for dotnet projects
if [ -z "$SUGGEST" ]; then
  CSPROJ=$(find "$GIT_ROOT" -maxdepth 2 -name '*.csproj' -o -name '*.sln' 2>/dev/null | head -1)
  [ -n "$CSPROJ" ] && SUGGEST="dotnet test"
fi

MSG="[dev-discipline:regression-guard] You are pushing/merging to main. Have you run the full test suite? Run tests before pushing to catch regressions."
if [ -n "$SUGGEST" ]; then
  MSG="$MSG Suggested command: $SUGGEST"
fi
MSG="$MSG To enable automatic test gating, create .dev-discipline/test-cmd with your test command."

printf 'WARN:%s' "$MSG"
exit 0
