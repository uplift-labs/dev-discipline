#!/bin/bash
# dev-discipline-run.sh — Dev Discipline multiplexer.
# Runs a group of guards, returns the highest-priority result.
#
# Usage: dev-discipline-run.sh <group>
# Groups: pre-bash | pre-edit-write | stop
#
# Input:  JSON on stdin (raw hook payload)
# Output: BLOCK:<reason> | ASK:<reason> | WARN:<context> | empty (allow)
# Exit:   always 0 (fail-open safety net)

set -u

GROUP="${1:-}"
[ -z "$GROUP" ] && { printf 'usage: dev-discipline-run.sh <group>\n' >&2; exit 0; }

# Global kill switches
[ "${CI:-}" = "true" ] && exit 0
[ "${DEV_DISCIPLINE_DISABLED:-}" = "1" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_DIR="$SCRIPT_DIR/../guards"

# Load config
. "$SCRIPT_DIR/../lib/config.sh"

# Map group to guard list
case "$GROUP" in
  pre-bash)        GUARDS="commit-checks regression-guard" ;;
  pre-edit-write)  GUARDS="rare-commits-reminder tdd-order-tracker" ;;
  stop)            GUARDS="rare-commits-reminder" ;;
  *) exit 0 ;;
esac

# Read stdin once
INPUT=$(cat)

# Priority tracking: BLOCK > ASK > WARN > pass
BEST_ASK=""
BEST_WARN=""

for guard in $GUARDS; do
  # Per-guard disable: DEV_DISCIPLINE_DISABLE_COMMIT_CHECKS=1, etc.
  env_name="DEV_DISCIPLINE_DISABLE_$(printf '%s' "$guard" | tr 'a-z-' 'A-Z_')"
  eval "[ \"\${${env_name}:-}\" = \"1\" ]" 2>/dev/null && continue

  RESULT=$(printf '%s' "$INPUT" | bash "$GUARD_DIR/$guard.sh" 2>/dev/null) || true

  case "$RESULT" in
    BLOCK:*)
      # Highest priority — short-circuit immediately
      printf '%s' "$RESULT"
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
done

# Output highest-priority non-block result
if [ -n "$BEST_ASK" ]; then
  printf '%s' "$BEST_ASK"
elif [ -n "$BEST_WARN" ]; then
  printf '%s' "$BEST_WARN"
fi

exit 0
