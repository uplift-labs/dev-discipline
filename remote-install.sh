#!/bin/bash
# remote-install.sh — One-command installer for dev-discipline.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/uplift-labs/dev-discipline/main/remote-install.sh | bash
#
# Options (via env vars):
#   DD_VERSION=v0.1.0        Install specific version (default: main)
#   DD_PREFIX=.uplift         Install prefix directory (default: .uplift)
#   DD_WITH_CLAUDE_CODE=1    Merge hooks into .claude/settings.json + inject CLAUDE.md rules
#   DD_WITH_CODEX=1          Merge hooks into .codex/hooks.json + inject AGENTS.md rules
#   DD_UNINSTALL=1           Remove dev-discipline
#   DD_DRY_RUN=1             Show what would be done without doing it

set -eu

VERSION="${DD_VERSION:-main}"
PREFIX="${DD_PREFIX:-.uplift}"
BASE_URL="https://raw.githubusercontent.com/uplift-labs/dev-discipline/$VERSION"
DRY_RUN="${DD_DRY_RUN:-0}"

# Detect git root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: not inside a git repository" >&2
  exit 1
}

# --- Migration from legacy path ---
migrate_old_path() {
  local old="$1" new="$2"
  [ -d "$old" ] || return 0
  [ -d "$new" ] && { printf '[migrate] both %s and %s exist — manual merge needed\n' "$old" "$new" >&2; return 1; }
  mkdir -p "$(dirname "$new")"
  mv "$old" "$new"
  printf '[migrate] moved %s → %s\n' "$old" "$new"
}

DD_DIR="$GIT_ROOT/$PREFIX/dev-discipline"

# --- Uninstall ---
if [ "${DD_UNINSTALL:-0}" = "1" ]; then
  echo "Uninstalling dev-discipline..."
  _MERGER=""
  # Check new path first, then legacy path
  for _try_dir in "$DD_DIR" "$GIT_ROOT/.dev-discipline"; do
    if [ -d "$_try_dir" ]; then
      [ -f "$_try_dir/core/lib/json-merge.py" ] && _MERGER="$_try_dir/core/lib/json-merge.py"
    fi
  done

  [ -z "$_MERGER" ] && echo "  No dev-discipline directory found — nothing to remove"

  SETTINGS="$GIT_ROOT/.claude/settings.json"
  if [ -f "$SETTINGS" ] && grep -q 'dev-discipline' "$SETTINGS" 2>/dev/null; then
    if [ -n "$_MERGER" ] && [ -f "$_MERGER" ]; then
      python3 "$_MERGER" "$SETTINGS" --uninstall
      echo "  Removed dev-discipline hooks from $SETTINGS"
    else
      echo "  NOTE: dev-discipline hooks remain in $SETTINGS — remove manually"
    fi
  fi

  CODEX_HOOKS="$GIT_ROOT/.codex/hooks.json"
  if [ -f "$CODEX_HOOKS" ] && grep -q 'dev-discipline' "$CODEX_HOOKS" 2>/dev/null; then
    if [ -n "$_MERGER" ] && [ -f "$_MERGER" ]; then
      python3 "$_MERGER" "$CODEX_HOOKS" --uninstall
      echo "  Removed dev-discipline hooks from $CODEX_HOOKS"
    else
      echo "  NOTE: dev-discipline hooks remain in $CODEX_HOOKS — remove manually"
    fi
  fi

  for _try_dir in "$DD_DIR" "$GIT_ROOT/.dev-discipline"; do
    if [ -d "$_try_dir" ]; then
      rm -rf "$_try_dir"
      echo "  Removed $_try_dir"
    fi
  done

  echo "Done."
  exit 0
fi

# --- Install ---
migrate_old_path "$GIT_ROOT/.dev-discipline" "$DD_DIR"
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
core/lib/json-merge.py
core/lib/toml-feature.py
adapter/hooks/pre-bash.sh
adapter/hooks/pre-edit.sh
adapter/hooks/stop.sh
adapter/codex/hooks/pre-bash.sh
adapter/codex/hooks/pre-edit.sh
adapter/codex/hooks/stop.sh
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

  # Download hooks template and patch paths for actual PREFIX
  HOOKS_SRC="$DD_DIR/settings-hooks.json"
  curl -fsSL "$BASE_URL/templates/settings-hooks.json" -o "$HOOKS_SRC" 2>/dev/null || true
  if [ -f "$HOOKS_SRC" ]; then
    sed -i "s|/\\.dev-discipline/adapter/hooks/|/$PREFIX/dev-discipline/adapter/hooks/|g" "$HOOKS_SRC"
  fi

  if [ -f "$HOOKS_SRC" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] Merge hooks into $SETTINGS"
    else
      python3 "$DD_DIR/core/lib/json-merge.py" "$SETTINGS" "$HOOKS_SRC"
      echo "  Merged dev-discipline hooks into $SETTINGS"
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

# --- Codex integration ---
if [ "${DD_WITH_CODEX:-0}" = "1" ]; then
  echo "  Integrating with Codex..."
  CODEX_DIR="$GIT_ROOT/.codex"
  CODEX_HOOKS="$CODEX_DIR/hooks.json"
  CODEX_CONFIG="$CODEX_DIR/config.toml"

  mkdir -p "$CODEX_DIR"

  # Download hooks template and patch paths for actual PREFIX
  CODEX_HOOKS_SRC="$DD_DIR/codex-hooks.json"
  curl -fsSL "$BASE_URL/templates/codex-hooks.json" -o "$CODEX_HOOKS_SRC" 2>/dev/null || true
  if [ -f "$CODEX_HOOKS_SRC" ]; then
    sed -i "s|/\\.dev-discipline/adapter/codex/hooks/|/$PREFIX/dev-discipline/adapter/codex/hooks/|g" "$CODEX_HOOKS_SRC"
  fi

  if [ -f "$CODEX_HOOKS_SRC" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] Merge Codex hooks into $CODEX_HOOKS"
    else
      python3 "$DD_DIR/core/lib/json-merge.py" "$CODEX_HOOKS" "$CODEX_HOOKS_SRC"
      echo "  Merged dev-discipline hooks into $CODEX_HOOKS"
    fi
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] Enable features.codex_hooks in $CODEX_CONFIG"
  else
    python3 "$DD_DIR/core/lib/toml-feature.py" "$CODEX_CONFIG" codex_hooks
    echo "  Enabled Codex hooks in $CODEX_CONFIG"
  fi

  # Inject AGENTS.md rules
  AGENTS_MD="$GIT_ROOT/AGENTS.md"
  RULES=$(curl -fsSL "$BASE_URL/templates/agents-md-rules.md" 2>/dev/null) || RULES=""
  if [ -n "$RULES" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] Append rules to $AGENTS_MD"
    else
      if [ -f "$AGENTS_MD" ]; then
        if ! grep -q 'dev-discipline' "$AGENTS_MD" 2>/dev/null; then
          printf '\n%s\n' "$RULES" >> "$AGENTS_MD"
          echo "  Appended rules to $AGENTS_MD"
        else
          echo "  Rules already present in $AGENTS_MD"
        fi
      else
        printf '%s\n' "$RULES" > "$AGENTS_MD"
        echo "  Created $AGENTS_MD with dev-discipline rules"
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
echo "  force-push-guard      — force push protection"
echo "  main-branch-commit-guard — protected branch commit reminder"
echo "  todo-debt-tracker     — net new TODO/FIXME debt at session end"
echo ""
echo "Configure: $DD_DIR/config"
echo "Opt-in test gate: echo 'your-test-cmd' > $DD_DIR/test-cmd"
