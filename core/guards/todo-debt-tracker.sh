#!/bin/bash
# todo-debt-tracker.sh — Dev Discipline Guard
# Counts net new TODO/FIXME/HACK/XXX markers added during session.
# Fires at session Stop to create awareness of accumulated tech debt.
#
# Input: JSON on stdin (hook payload)
# Output: ASK:<reason> | WARN:<context> | empty (allow)

set -u

INPUT=$(cat)
. "$(dirname "$0")/../lib/config.sh"

# Config defaults
: "${TODO_DEBT_THRESHOLD:=5}"
: "${TODO_DEBT_PATTERNS:=TODO,FIXME,HACK,XXX}"

# Build grep pattern from config: TODO,FIXME -> \bTODO\b|\bFIXME\b
GREP_PAT=""
IFS=',' read -ra _pats <<< "$TODO_DEBT_PATTERNS"
for _p in "${_pats[@]}"; do
  _p=$(printf '%s' "$_p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$_p" ] && continue
  [ -n "$GREP_PAT" ] && GREP_PAT="$GREP_PAT|"
  GREP_PAT="${GREP_PAT}\\b${_p}\\b"
done
[ -z "$GREP_PAT" ] && exit 0

# Get diff of uncommitted changes
DIFF=$(git diff HEAD 2>/dev/null | head -5000)
# Fallback for repos with no commits yet
if [ -z "$DIFF" ]; then
  DIFF=$(git diff --cached 2>/dev/null | head -5000)
fi
[ -z "$DIFF" ] && exit 0

# Count added TODO lines (lines starting with +, excluding +++ headers)
ADDED=$(printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' | grep -ciE "$GREP_PAT" || true)
: "${ADDED:=0}"

# Count removed TODO lines (lines starting with -, excluding --- headers)
REMOVED=$(printf '%s\n' "$DIFF" | grep '^-' | grep -v '^---' | grep -ciE "$GREP_PAT" || true)
: "${REMOVED:=0}"

# Net new (floor at 0)
NET=$((ADDED - REMOVED))
[ "$NET" -le 0 ] && exit 0

if [ "$NET" -gt "$TODO_DEBT_THRESHOLD" ]; then
  printf 'ASK:[dev-discipline:todo-debt] Session added %s net new TODO/FIXME marker(s) (threshold: %s). Resolve before ending session.' "$NET" "$TODO_DEBT_THRESHOLD"
else
  printf 'WARN:[dev-discipline:todo-debt] Session added %s net new TODO/FIXME marker(s). Consider resolving before ending.' "$NET"
fi

exit 0
