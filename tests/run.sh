#!/bin/bash
# run.sh — Dev Discipline test runner.
# Fixture-driven: for each guard, runs tp-*.json (expect trigger) and tn-*.json (expect pass).
#
# Usage: bash tests/run.sh [guard-name]
# Exit: 0 if all pass, 1 if any fail.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_DIR="$ROOT/core/guards"
FIXTURE_DIR="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0
ERRORS=""

# Optional filter
FILTER="${1:-}"

run_fixture() {
  local guard="$1"
  local fixture="$2"
  local fixture_name
  fixture_name=$(basename "$fixture" .json)

  # Determine expected outcome from filename prefix
  local expected
  case "$fixture_name" in
    tp-*) expected="trigger" ;;
    tn-*) expected="pass" ;;
    *) return ;; # skip non-fixture files
  esac

  # Set up temp git repo for guards that need git context
  local TMPDIR
  TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'dd-test')
  (
    cd "$TMPDIR" || exit 1
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Guard-specific env setup
    case "$guard" in
      rare-commits-reminder)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        case "$fixture_name" in
          tp-many-files*)
            for i in $(seq 1 8); do echo "f$i" > "file$i.txt"; done
            ;;
          tp-many-insertions*)
            echo "init" > bigfile.py
            git add bigfile.py
            git commit -q -m "feat: add bigfile"
            for i in $(seq 1 120); do echo "line $i" >> bigfile.py; done
            ;;
          tn-few-changes*)
            echo "small" > one.txt
            ;;
        esac
        ;;
      regression-guard)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        case "$fixture_name" in
          tp-push-failing*)
            mkdir -p .dev-discipline
            echo "exit 1" > .dev-discipline/test-cmd
            ;;
          tn-push-tests-pass*)
            mkdir -p .dev-discipline
            echo "exit 0" > .dev-discipline/test-cmd
            ;;
        esac
        ;;
      tdd-order-tracker)
        # Clean session state
        rm -f /tmp/dd-tdd-tracker-test-session-* 2>/dev/null
        ;;
      commit-checks)
        case "$fixture_name" in
          *aws-key-staged*)
            mkdir -p src
            echo "x=1" > src/main.py
            git add src/main.py
            git commit -q -m "feat: init"
            printf 'AWS_KEY = "AKIAIOSFODNN7EXAMPLE1"\n' > src/config.py
            git add src/config.py
            ;;
          *secret-in-test*)
            mkdir -p tests
            echo "x=1" > README.md
            git add README.md
            git commit -q -m "feat: init"
            printf 'MOCK_KEY = "AKIAIOSFODNN7EXAMPLE1"\n' > tests/test_keys.py
            git add tests/test_keys.py
            ;;
          *code-only*|*code-and-test*)
            mkdir -p src tests
            echo "x=1" > src/main.py
            git add src/main.py
            case "$fixture_name" in
              *code-and-test*)
                echo "assert True" > tests/test_main.py
                git add tests/test_main.py
                ;;
            esac
            git commit -q -m "feat: init"
            echo "x=2" > src/main.py
            git add src/main.py
            case "$fixture_name" in
              *code-and-test*)
                echo "assert 1+1==2" > tests/test_main.py
                git add tests/test_main.py
                ;;
            esac
            ;;
          *)
            echo "init" > README.md
            git add README.md
            git commit -q -m "feat: init"
            ;;
        esac
        ;;
      dead-branch-guard)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        case "$fixture_name" in
          tp-checkout-main-dirty*|tp-switch-feature-dirty*)
            echo "dirty" > untracked.txt
            ;;
          tn-checkout-new-branch*)
            echo "dirty" > untracked.txt
            ;;
          # tn-checkout-clean: no dirty files
          # tn-checkout-file-restore: no dirty files needed (-- filter)
        esac
        ;;
      force-push-guard)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        ;;
      main-branch-commit-guard)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        case "$fixture_name" in
          tp-commit-on-main*)
            # Already on main (default branch after init) — stay here
            ;;
          tp-commit-on-master*)
            # Rename default branch to master
            git branch -m master
            ;;
          tn-commit-on-feature*)
            git checkout -q -b feature/x
            ;;
          tn-merge-commit-on-main*)
            # Simulate merge in progress: create MERGE_HEAD
            _git_dir=$(git rev-parse --git-dir)
            _head=$(git rev-parse HEAD)
            printf '%s\n' "$_head" > "$_git_dir/MERGE_HEAD"
            ;;
        esac
        ;;
      todo-debt-tracker)
        echo "init" > README.md
        git add README.md
        git commit -q -m "feat: init"
        case "$fixture_name" in
          tp-new-todos*)
            printf '// TODO: fix this\n// FIXME: cleanup\ncode();\n' > src.js
            git add src.js
            ;;
          tp-many-todos*)
            for i in $(seq 1 7); do echo "// TODO: item $i" >> src.js; done
            git add src.js
            ;;
          tn-removed-todos*)
            printf '// TODO: old item\ncode();\n' > src.js
            git add src.js
            git commit -q -m "feat: add src"
            printf 'code();\n' > src.js
            ;;
          # tn-no-todos: clean, no TODO markers
        esac
        ;;
    esac

    # Run the guard with fixture as stdin
    RESULT=$(bash "$GUARD_DIR/$guard.sh" < "$fixture" 2>/dev/null) || true

    # Classify result
    local triggered=0
    case "$RESULT" in
      BLOCK:*|ASK:*|WARN:*) triggered=1 ;;
    esac

    if [ "$expected" = "trigger" ] && [ "$triggered" -eq 1 ]; then
      echo "PASS"
    elif [ "$expected" = "pass" ] && [ "$triggered" -eq 0 ]; then
      echo "PASS"
    else
      echo "FAIL:$RESULT"
    fi
  )

  # Cleanup
  rm -rf "$TMPDIR" 2>/dev/null
}

# Run all fixtures
for guard_dir in "$FIXTURE_DIR"/*/; do
  guard=$(basename "$guard_dir")
  [ -n "$FILTER" ] && [ "$guard" != "$FILTER" ] && continue
  [ ! -f "$GUARD_DIR/$guard.sh" ] && continue

  for fixture in "$guard_dir"*.json; do
    [ ! -f "$fixture" ] && continue
    fixture_name=$(basename "$fixture" .json)

    OUTPUT=$(run_fixture "$guard" "$fixture")

    if [ "$OUTPUT" = "PASS" ]; then
      PASS=$((PASS + 1))
      printf '  \033[32mPASS\033[0m  %s/%s\n' "$guard" "$fixture_name"
    else
      FAIL=$((FAIL + 1))
      DETAIL="${OUTPUT#FAIL:}"
      printf '  \033[31mFAIL\033[0m  %s/%s  (got: %s)\n' "$guard" "$fixture_name" "$DETAIL"
      ERRORS="$ERRORS\n  $guard/$fixture_name"
    fi
  done
done

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  printf "\nFailed tests:%b\n" "$ERRORS"
  exit 1
fi
exit 0
