#!/bin/bash
# test-adapter-codex.sh — Tests for Codex hook adapters.
# Usage: bash tests/test-adapter-codex.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRE_BASH="$ROOT/adapter/codex/hooks/pre-bash.sh"
PRE_EDIT="$ROOT/adapter/codex/hooks/pre-edit.sh"
STOP_HOOK="$ROOT/adapter/codex/hooks/stop.sh"

PASS=0
FAIL=0
ERRORS=""

check_contains() {
  local name="$1"
  local actual="$2"
  local expected="$3"

  if printf '%s' "$actual" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    printf "  \033[32mPASS\033[0m %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $name\n    expected substring: $expected\n    actual: $actual"
    printf "  \033[31mFAIL\033[0m %s\n" "$name"
  fi
}

check_empty() {
  local name="$1"
  local actual="$2"

  if [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  \033[32mPASS\033[0m %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $name\n    expected empty output\n    actual: $actual"
    printf "  \033[31mFAIL\033[0m %s\n" "$name"
  fi
}

new_repo() {
  local dir
  dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'dd-codex-test')
  (
    cd "$dir" || exit 1
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    printf 'init\n' > README.md
    git add README.md
    git commit -q -m "feat: init"
  )
  printf '%s' "$dir"
}

run_hook() {
  local hook="$1"
  local input="$2"
  printf '%s' "$input" | bash "$hook" 2>/dev/null || true
}

echo "=== Codex adapter tests ==="

# --- PreToolUse Bash: BLOCK -> permission deny ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  INPUT='{"hook_event_name":"PreToolUse","session_id":"codex-bad-commit","tool_name":"Bash","tool_input":{"command":"git commit -m \"bad\""}}'
  OUTPUT=$(run_hook "$PRE_BASH" "$INPUT")
  check_contains "pre-bash maps BLOCK to deny" "$OUTPUT" '"permissionDecision":"deny"'
  check_contains "pre-bash preserves guard reason" "$OUTPUT" "commit-checks"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- PreToolUse Bash: ASK -> deny by default for Codex ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  INPUT='{"hook_event_name":"PreToolUse","session_id":"codex-force-push","tool_name":"Bash","tool_input":{"command":"git push --force origin feature/x"}}'
  OUTPUT=$(run_hook "$PRE_BASH" "$INPUT")
  check_contains "pre-bash maps ASK to deny by default" "$OUTPUT" '"permissionDecision":"deny"'
  check_contains "pre-bash ASK reason is retained" "$OUTPUT" "force-push"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- PreToolUse Bash: WARN -> systemMessage ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  mkdir -p src
  printf 'x = 1\n' > src/main.py
  git add src/main.py
  INPUT='{"hook_event_name":"PreToolUse","session_id":"codex-code-no-test","tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: change\""}}'
  OUTPUT=$(run_hook "$PRE_BASH" "$INPUT")
  check_contains "pre-bash maps WARN to systemMessage" "$OUTPUT" '"systemMessage"'
  check_contains "pre-bash warning text is retained" "$OUTPUT" "Committing code without test files"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- PreToolUse apply_patch: code before test warns ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  rm -f /tmp/dd-tdd-tracker-codex-edit-warn 2>/dev/null
  PATCH='*** Begin Patch\n*** Add File: src/main.py\n+print(1)\n*** End Patch'
  INPUT=$(printf '{"hook_event_name":"PreToolUse","session_id":"codex-edit-warn","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$PATCH")
  OUTPUT=$(run_hook "$PRE_EDIT" "$INPUT")
  check_contains "pre-edit maps TDD WARN to systemMessage" "$OUTPUT" '"systemMessage"'
  check_contains "pre-edit warning text is retained" "$OUTPUT" "tdd-order"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- PreToolUse apply_patch: TDD mode blocks code before test ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  rm -f /tmp/dd-tdd-tracker-codex-edit-block 2>/dev/null
  mkdir -p .dev-discipline
  : > .dev-discipline/.tdd-mode
  PATCH='*** Begin Patch\n*** Add File: src/main.py\n+print(1)\n*** End Patch'
  INPUT=$(printf '{"hook_event_name":"PreToolUse","session_id":"codex-edit-block","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$PATCH")
  OUTPUT=$(run_hook "$PRE_EDIT" "$INPUT")
  check_contains "pre-edit maps TDD BLOCK to deny" "$OUTPUT" '"permissionDecision":"deny"'
  check_contains "pre-edit block reason is retained" "$OUTPUT" "Write tests first"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- PreToolUse apply_patch: test before code in same patch passes ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  rm -f /tmp/dd-tdd-tracker-codex-edit-pass 2>/dev/null
  PATCH='*** Begin Patch\n*** Add File: tests/test_main.py\n+assert True\n*** Add File: src/main.py\n+print(1)\n*** End Patch'
  INPUT=$(printf '{"hook_event_name":"PreToolUse","session_id":"codex-edit-pass","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$PATCH")
  OUTPUT=$(run_hook "$PRE_EDIT" "$INPUT")
  check_empty "pre-edit allows test-before-code patch" "$OUTPUT"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

# --- Stop: ASK/BLOCK -> continuation decision ---
TMPDIR=$(new_repo)
pushd "$TMPDIR" >/dev/null || exit 1
  for i in $(seq 1 7); do printf '// TODO: item %s\n' "$i" >> src.js; done
  git add src.js
  INPUT='{"hook_event_name":"Stop","session_id":"codex-stop-todo","turn_id":"turn-1"}'
  OUTPUT=$(run_hook "$STOP_HOOK" "$INPUT")
  check_contains "stop maps ASK to continuation block" "$OUTPUT" '"decision":"block"'
  check_contains "stop continuation reason is retained" "$OUTPUT" "todo-debt"
popd >/dev/null || exit 1
rm -rf "$TMPDIR" 2>/dev/null

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf "%b\n" "$ERRORS"
  exit 1
fi
exit 0
