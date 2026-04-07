#!/bin/bash
# main-branch-commit-guard.sh — Dev Discipline Guard
# Warns when committing directly to a protected branch (main/master).
# Encourages feature branch + PR workflow.
#
# Input: JSON on stdin (hook payload with "command" field)
# Output: WARN:<context> | empty (allow)

set -u

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"
. "$(dirname "$0")/../lib/config.sh"

# Config: allow disabling this guard via config
: "${MAIN_BRANCH_COMMIT_GUARD:=1}"
[ "$MAIN_BRANCH_COMMIT_GUARD" != "1" ] && exit 0

CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0

# Only trigger on git commit
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Filter: allow-empty commits (CI triggers)
case "$CMD" in
  *"--allow-empty"*) exit 0 ;;
esac

# Filter: merge commits (completing a merge on main is normal flow)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
[ -f "$GIT_DIR/MERGE_HEAD" ] && exit 0

# Get current branch
CURRENT=$(git branch --show-current 2>/dev/null) || exit 0
[ -z "$CURRENT" ] && exit 0  # detached HEAD — not a branch commit

# Check if current branch is protected
: "${DEAD_BRANCH_PROTECTED:=main,master}"
IS_PROTECTED=0
IFS=',' read -ra _branches <<< "$DEAD_BRANCH_PROTECTED"
for _b in "${_branches[@]}"; do
  _b=$(printf '%s' "$_b" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$CURRENT" = "$_b" ] && IS_PROTECTED=1
done

if [ "$IS_PROTECTED" -eq 1 ]; then
  printf 'WARN:[dev-discipline:main-branch-commit] Committing directly to protected branch '\''%s'\''. Consider using a feature branch and pull request.' "$CURRENT"
fi

exit 0
