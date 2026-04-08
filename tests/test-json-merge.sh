#!/bin/bash
# test-json-merge.sh — Tests for core/lib/json-merge.py
# Usage: bash tests/test-json-merge.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MERGE="$ROOT/core/lib/json-merge.py"

PASS=0
FAIL=0
ERRORS=""

check() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  \033[32mPASS\033[0m %s\n" "$name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $name\n    expected: $expected\n    actual:   $actual"
    printf "  \033[31mFAIL\033[0m %s\n" "$name"
  fi
}

# Helper: query a JSON file via python, passing path as argv (MSYS-safe)
json_query() {
  local file="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($expr)" "$file"
}

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'dd-merge-test')
trap 'rm -rf "$TMPDIR"' EXIT

# --- Source hooks template ---
cat > "$TMPDIR/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .dev-discipline/adapter/hooks/pre-bash.sh",
            "timeout": 120000
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .dev-discipline/adapter/hooks/stop.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
EOF

echo "=== json-merge tests ==="

# --- Test 1: merge into non-existent target (fresh install) ---
rm -f "$TMPDIR/target1.json"
python3 "$MERGE" "$TMPDIR/target1.json" "$TMPDIR/hooks.json"
ACTUAL=$(json_query "$TMPDIR/target1.json" "len(d.get('hooks',{}).get('PreToolUse',[]))")
check "fresh install creates hooks" "1" "$ACTUAL"

# --- Test 2: idempotent — running twice produces same result ---
cp "$TMPDIR/target1.json" "$TMPDIR/target2.json"
python3 "$MERGE" "$TMPDIR/target2.json" "$TMPDIR/hooks.json"
DIFF=$(diff "$TMPDIR/target1.json" "$TMPDIR/target2.json" 2>&1) || true
check "idempotent merge" "" "$DIFF"

# --- Test 3: merge into existing settings with other hooks ---
cat > "$TMPDIR/target3.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .safeguard/adapter/hooks/pre-bash.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": ["Bash"]
  }
}
EOF
python3 "$MERGE" "$TMPDIR/target3.json" "$TMPDIR/hooks.json"

HOOK_COUNT=$(json_query "$TMPDIR/target3.json" \
  "len([g for g in d['hooks']['PreToolUse'] if g.get('matcher')=='Bash'][0]['hooks'])")
check "merge preserves existing hooks" "2" "$HOOK_COUNT"

HAS_PERMS=$(json_query "$TMPDIR/target3.json" "'yes' if 'permissions' in d else 'no'")
check "merge preserves non-hook settings" "yes" "$HAS_PERMS"

HAS_STOP=$(json_query "$TMPDIR/target3.json" "'yes' if 'Stop' in d.get('hooks',{}) else 'no'")
check "merge adds new event types" "yes" "$HAS_STOP"

# --- Test 4: uninstall removes only dd hooks ---
cp "$TMPDIR/target3.json" "$TMPDIR/target4.json"
python3 "$MERGE" "$TMPDIR/target4.json" --uninstall

SG_HOOK=$(json_query "$TMPDIR/target4.json" \
  "[g for g in d['hooks']['PreToolUse'] if g.get('matcher')=='Bash'][0]['hooks'][0]['command']")
check "uninstall keeps non-dd hooks" "bash .safeguard/adapter/hooks/pre-bash.sh" "$SG_HOOK"

DD_HOOKS=$(json_query "$TMPDIR/target4.json" \
  "sum(1 for h in [g for g in d['hooks']['PreToolUse'] if g.get('matcher')=='Bash'][0]['hooks'] if '.dev-discipline/' in h.get('command',''))")
check "uninstall removes dd hooks" "0" "$DD_HOOKS"

HAS_PERMS2=$(json_query "$TMPDIR/target4.json" "'yes' if 'permissions' in d else 'no'")
check "uninstall preserves non-hook settings" "yes" "$HAS_PERMS2"

# --- Test 5: uninstall all hooks removes hooks key entirely ---
cat > "$TMPDIR/target5.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .dev-discipline/adapter/hooks/pre-bash.sh"
          }
        ]
      }
    ]
  }
}
EOF
python3 "$MERGE" "$TMPDIR/target5.json" --uninstall
if [ ! -f "$TMPDIR/target5.json" ]; then
  check "uninstall deletes empty file" "deleted" "deleted"
else
  check "uninstall deletes empty file" "deleted" "exists"
fi

# --- Test 6: merge with new matcher group ---
cat > "$TMPDIR/target6.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo existing"
          }
        ]
      }
    ]
  }
}
EOF
cat > "$TMPDIR/hooks6.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash .dev-discipline/adapter/hooks/pre-edit.sh"
          }
        ]
      }
    ]
  }
}
EOF
python3 "$MERGE" "$TMPDIR/target6.json" "$TMPDIR/hooks6.json"
MATCHER_COUNT=$(json_query "$TMPDIR/target6.json" "len(d['hooks']['PreToolUse'])")
check "merge adds new matcher groups" "2" "$MATCHER_COUNT"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
