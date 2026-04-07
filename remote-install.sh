#!/bin/bash
# remote-install.sh — One-command installer for dev-discipline.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | bash
#
# Options (via env vars):
#   DD_VERSION=v0.1.0        Install specific version (default: main)
#   DD_WITH_CLAUDE_CODE=1    Merge hooks into .claude/settings.json + inject CLAUDE.md rules
#   DD_UNINSTALL=1           Remove dev-discipline
#   DD_DRY_RUN=1             Show what would be done without doing it

set -eu

VERSION="${DD_VERSION:-main}"
BASE_URL="https://raw.githubusercontent.com/uplift-labs/dev-discipline/$VERSION"
DRY_RUN="${DD_DRY_RUN:-0}"

# Detect git root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: not inside a git repository" >&2
  exit 1
}

DD_DIR="$GIT_ROOT/.dev-discipline"

# --- Uninstall ---
if [ "${DD_UNINSTALL:-0}" = "1" ]; then
  echo "Uninstalling dev-discipline..."
  if [ -d "$DD_DIR" ]; then
    rm -rf "$DD_DIR"
    echo "  Removed $DD_DIR"
  else
    echo "  $DD_DIR not found — nothing to remove"
  fi
  SETTINGS="$GIT_ROOT/.claude/settings.json"
  if [ -f "$SETTINGS" ] && grep -q 'dev-discipline' "$SETTINGS" 2>/dev/null; then
    echo "  NOTE: dev-discipline hooks remain in $SETTINGS — remove manually"
  fi
  echo "Done."
  exit 0
fi

# --- Install ---
echo "Installing dev-discipline $VERSION..."

FILES="
core/cmd/dev-discipline-run.sh
core/guards/commit-checks.sh
core/guards/regression-guard.sh
core/guards/rare-commits-reminder.sh
core/guards/tdd-order-tracker.sh
core/guards/dead-branch-guard.sh
core/guards/todo-debt-tracker.sh
core/guards/force-push-guard.sh
core/guards/main-branch-commit-guard.sh
core/lib/json-field.sh
core/lib/config.sh
adapter/hooks/pre-bash.sh
adapter/hooks/pre-edit.sh
adapter/hooks/stop.sh
"

# Create directories
for f in $FILES; do
  dir=$(dirname "$DD_DIR/$f")
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] mkdir -p $dir"
  else
    mkdir -p "$dir"
  fi
done

# Download files
FAILED=0
for f in $FILES; do
  url="$BASE_URL/$f"
  dest="$DD_DIR/$f"
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] curl $url -> $dest"
  else
    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
      chmod +x "$dest"
    else
      echo "  WARNING: failed to download $f" >&2
      FAILED=$((FAILED + 1))
    fi
  fi
done

if [ "$FAILED" -gt 0 ]; then
  echo "WARNING: $FAILED files failed to download. Installation may be incomplete." >&2
fi

# Create default config (only if absent)
if [ ! -f "$DD_DIR/config" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] Create $DD_DIR/config from defaults"
  else
    curl -fsSL "$BASE_URL/templates/config.default" -o "$DD_DIR/config" 2>/dev/null || {
      cat > "$DD_DIR/config" << 'CONF'
# dev-discipline configuration
TDD_MODE=0
RARE_COMMITS_MAX_FILES=5
RARE_COMMITS_MAX_INSERTIONS=100
WHITELIST_PATTERNS=
CONF
    }
  fi
else
  echo "  Config exists — keeping $DD_DIR/config"
fi

# Write version marker
if [ "$DRY_RUN" != "1" ]; then
  echo "$VERSION" > "$DD_DIR/.version"
fi

# --- Claude Code integration ---
if [ "${DD_WITH_CLAUDE_CODE:-0}" = "1" ]; then
  echo "  Integrating with Claude Code..."
  SETTINGS_DIR="$GIT_ROOT/.claude"
  SETTINGS="$SETTINGS_DIR/settings.json"

  mkdir -p "$SETTINGS_DIR"

  HOOKS_JSON=$(curl -fsSL "$BASE_URL/templates/settings-hooks.json" 2>/dev/null) || HOOKS_JSON=""

  if [ -n "$HOOKS_JSON" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] Merge hooks into $SETTINGS"
    else
      if [ -f "$SETTINGS" ]; then
        if ! grep -q 'dev-discipline' "$SETTINGS" 2>/dev/null; then
          echo "  NOTE: Add dev-discipline hooks to $SETTINGS manually."
          echo "  Template saved to $DD_DIR/settings-hooks.json"
          printf '%s' "$HOOKS_JSON" > "$DD_DIR/settings-hooks.json"
        else
          echo "  Hooks already present in $SETTINGS"
        fi
      else
        printf '%s' "$HOOKS_JSON" > "$SETTINGS"
        echo "  Created $SETTINGS with dev-discipline hooks"
      fi
    fi
  fi

  # Inject CLAUDE.md rules
  CLAUDE_MD="$GIT_ROOT/CLAUDE.md"
  RULES=$(curl -fsSL "$BASE_URL/templates/claude-md-rules.md" 2>/dev/null) || RULES=""
  if [ -n "$RULES" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] Append rules to $CLAUDE_MD"
    else
      if [ -f "$CLAUDE_MD" ]; then
        if ! grep -q 'dev-discipline' "$CLAUDE_MD" 2>/dev/null; then
          printf '\n%s\n' "$RULES" >> "$CLAUDE_MD"
          echo "  Appended rules to $CLAUDE_MD"
        else
          echo "  Rules already present in $CLAUDE_MD"
        fi
      else
        printf '%s\n' "$RULES" > "$CLAUDE_MD"
        echo "  Created $CLAUDE_MD with dev-discipline rules"
      fi
    fi
  fi
fi

echo ""
echo "dev-discipline $VERSION installed to $DD_DIR"
echo ""
echo "Guards:"
echo "  commit-checks         — conventional commit format + secret scanning"
echo "  regression-guard      — test suite gate before push/merge"
echo "  rare-commits-reminder — uncommitted work detector"
echo "  tdd-order-tracker     — test-before-code order tracking"
echo "  dead-branch-guard     — branch switch with uncommitted changes"
echo "  todo-debt-tracker     — net new TODO/FIXME debt at session end"
echo ""
echo "Configure: $DD_DIR/config"
echo "Opt-in test gate: echo 'your-test-cmd' > $DD_DIR/test-cmd"
