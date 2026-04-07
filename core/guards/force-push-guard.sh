#!/bin/bash
# force-push-guard.sh — Dev Discipline Guard
# Blocks/warns on git push --force to prevent overwriting remote history.
#
# Input: JSON on stdin (hook payload with "command" field)
# Output: BLOCK:<reason> | ASK:<reason> | WARN:<context> | empty (allow)

set -u

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"
. "$(dirname "$0")/../lib/config.sh"

CMD=$(json_field_long "command" "$INPUT")
[ -z "$CMD" ] && exit 0

# Only trigger on git push
case "$CMD" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# Detect force flags (check --force-with-lease BEFORE --force to avoid substring match)
HAS_FORCE_LEASE=0
HAS_FORCE=0
case "$CMD" in
  *"--force-with-lease"*) HAS_FORCE_LEASE=1 ;;
esac
case "$CMD" in
  *"--force"*) HAS_FORCE=1 ;;
  *" -f "*|*" -f"$) HAS_FORCE=1 ;;
esac
# --force-with-lease contains --force as substring; disambiguate
if [ "$HAS_FORCE_LEASE" -eq 1 ] && [ "$HAS_FORCE" -eq 1 ]; then
  # Check if there's a standalone --force (not just --force-with-lease)
  _stripped=$(printf '%s' "$CMD" | sed 's/--force-with-lease//g')
  case "$_stripped" in
    *"--force"*|*" -f "*|*" -f"$) HAS_FORCE=1 ;;
    *) HAS_FORCE=0 ;;
  esac
fi

# No force flag — nothing to guard
[ "$HAS_FORCE" -eq 0 ] && [ "$HAS_FORCE_LEASE" -eq 0 ] && exit 0

# Extract target branch from command
# Pattern: git push [flags] [remote] [branch] or git push [flags] [remote] [local:]branch
TARGET=""
_args=$(printf '%s' "$CMD" | sed 's/.*git push//' | sed 's/^[[:space:]]*//')
for _arg in $_args; do
  case "$_arg" in
    -*) continue ;;  # skip flags
    *) TARGET="$_arg" ;;  # last non-flag arg = branch (or remote, then branch)
  esac
done
# TARGET may be "remote branch" — we want the last non-flag word
# Also handle refspec like "local:remote"
case "$TARGET" in
  *:*) TARGET="${TARGET#*:}" ;;
esac

# Fallback to current branch if no target found
if [ -z "$TARGET" ]; then
  TARGET=$(git branch --show-current 2>/dev/null) || true
fi

# Check if target is a protected branch
: "${DEAD_BRANCH_PROTECTED:=main,master}"
IS_PROTECTED=0
IFS=',' read -ra _branches <<< "$DEAD_BRANCH_PROTECTED"
for _b in "${_branches[@]}"; do
  _b=$(printf '%s' "$_b" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$TARGET" = "$_b" ] && IS_PROTECTED=1
done

if [ "$HAS_FORCE" -eq 1 ]; then
  if [ "$IS_PROTECTED" -eq 1 ]; then
    printf 'BLOCK:[dev-discipline:force-push] Force push to protected branch '\''%s'\'' will overwrite remote history. Use --force-with-lease or push normally.' "$TARGET"
  else
    printf 'ASK:[dev-discipline:force-push] Force pushing to '\''%s'\'' will overwrite remote history. Are you sure?' "$TARGET"
  fi
elif [ "$HAS_FORCE_LEASE" -eq 1 ]; then
  if [ "$IS_PROTECTED" -eq 1 ]; then
    printf 'WARN:[dev-discipline:force-push] Force push with lease to protected branch '\''%s'\''. Consider pushing normally.' "$TARGET"
  fi
  # --force-with-lease to non-protected: safe enough, exit 0
fi

exit 0
