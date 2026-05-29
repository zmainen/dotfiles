#!/usr/bin/env bash
# Install personal Claude Code config from dotfiles:
#   1. Symlink global skills into ~/.claude/skills/ (dotfiles = single source of truth)
#   2. Register user-scope MCP servers
#
# Re-running is safe (idempotent). Skills are symlinked, so edits in the
# dotfiles repo take effect immediately.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/skills"
for s in "$DIR"/skills/*/; do
  name="$(basename "$s")"
  target="$HOME/.claude/skills/$name"
  rm -rf "$target"
  ln -s "${s%/}" "$target"
  echo "linked skill: $name"
done

bash "$DIR/setup-user-mcp.sh"
echo "Done. Open a new Claude Code session to pick up the changes."
