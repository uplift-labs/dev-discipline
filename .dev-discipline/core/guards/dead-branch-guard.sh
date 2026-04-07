#!/bin/bash
# dead-branch-guard.sh — Dev Discipline Guard
# Warns/blocks when switching branches with uncommitted changes.
# Git silently carries non-conflicting uncommitted changes to the target branch,
# which can cause agents to commit work to the wrong branch.
#
# Input: JSON on stdin (hook payload with "command" field)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)

set -u

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"
. "$(dirname "$0")/../lib/config.sh"

CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0

# Only trigger on git checkout / git switch (branch-switching intent)
IS_CHECKOUT=0
IS_SWITCH=0
case "$CMD" in
  *"git checkout"*) IS_CHECKOUT=1 ;;
  *"git switch"*)   IS_SWITCH=1 ;;
esac
[ "$IS_CHECKOUT" -eq 0 ] && [ "$IS_SWITCH" -eq 0 ] && exit 0

# Filter out branch creation (safe even with dirty worktree)
case "$CMD" in
  *" -b "*|*" -b"$|*" -B "*|*" -B"$) exit 0 ;;
  *"--orphan"*)                       exit 0 ;;
  *" -c "*|*" -c"$|*" -C "*|*" -C"$) exit 0 ;;
  *"--create"*|*"--force-create"*)    exit 0 ;;
esac

# Filter out file restore (not a branch switch)
case "$CMD" in
  *" -- "*|*" -- "$) exit 0 ;;
esac
# git checkout . or git checkout ./path — file restore
if [ "$IS_CHECKOUT" -eq 1 ]; then
  # Extract what comes after "git checkout" (strip flags)
  _tail=$(printf '%s' "$CMD" | sed 's/.*git checkout//' | sed 's/^[[:space:]]*//')
  case "$_tail" in
    .|./*) exit 0 ;;
  esac
fi

# Check if worktree is dirty
DIRTY=$(git status --porcelain 2>/dev/null | head -20)
[ -z "$DIRTY" ] && exit 0

DIRTY_COUNT=$(printf '%s\n' "$DIRTY" | wc -l | tr -d ' ')

# Extract target branch name (last non-flag argument after git checkout/switch)
TARGET=""
if [ "$IS_CHECKOUT" -eq 1 ]; then
  TARGET=$(printf '%s' "$CMD" | sed 's/.*git checkout//' | sed 's/^[[:space:]]*//' | awk '{print $NF}')
elif [ "$IS_SWITCH" -eq 1 ]; then
  TARGET=$(printf '%s' "$CMD" | sed 's/.*git switch//' | sed 's/^[[:space:]]*//' | awk '{print $NF}')
fi

# Check if target is a protected branch
: "${DEAD_BRANCH_PROTECTED:=main,master}"
IS_PROTECTED=0
IFS=',' read -ra _branches <<< "$DEAD_BRANCH_PROTECTED"
for _b in "${_branches[@]}"; do
  _b=$(printf '%s' "$_b" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$TARGET" = "$_b" ] && IS_PROTECTED=1
done

if [ "$IS_PROTECTED" -eq 1 ]; then
  printf 'BLOCK:[dev-discipline:dead-branch] %s uncommitted file(s). Switching to protected branch '\''%s'\'' will carry uncommitted changes. Commit or stash first.' "$DIRTY_COUNT" "$TARGET"
else
  printf 'WARN:[dev-discipline:dead-branch] %s uncommitted file(s). Switching to '\''%s'\'' will silently carry these changes. Consider committing or stashing first.' "$DIRTY_COUNT" "$TARGET"
fi

exit 0
