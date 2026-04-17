#!/bin/bash
# config.sh — Load .dev-discipline/config.
# Values from config file become defaults; env vars always override.
#
# Usage: . "$SCRIPT_DIR/../lib/config.sh"
#
# Config file format (shell-sourceable key=value):
#   TDD_MODE=0
#   RARE_COMMITS_MAX_FILES=5

_DD_ROOT="${DEV_DISCIPLINE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
# Derive install dir from this script's location (core/lib/config.sh → install root)
_DD_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"
_DD_CONFIG="${_DD_INSTALL_DIR:-${_DD_ROOT:-.}/.uplift/dev-discipline}/config"

if [ -f "$_DD_CONFIG" ]; then
  while IFS='=' read -r key value; do
    case "$key" in \#*|"") continue ;; esac
    key=$(printf '%s' "$key" | tr -d '[:space:]')
    value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    eval ": \${${key}:=${value}}" 2>/dev/null || true
  done < "$_DD_CONFIG"
fi

# Defaults (env vars or config values override these)
: "${TDD_MODE:=0}"
: "${RARE_COMMITS_MAX_FILES:=5}"
: "${RARE_COMMITS_MAX_INSERTIONS:=100}"
: "${WHITELIST_PATTERNS:=}"
