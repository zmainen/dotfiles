#!/usr/bin/env bash
# Register HAAK's promotable MCP servers at Claude Code USER scope (~/.claude.json),
# so they're available in every project, not just the HAAK repo.
#
# Idempotent: removes any existing same-name user entry first, then re-adds.
# Run after a fresh machine setup, or after changing a server's command/URL.
set -euo pipefail

add() {  # name, then -- command...  (or --transport http <url>)
  local name="$1"; shift
  claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
  claude mcp add "$name" --scope user "$@"
}

# stdio servers (commands must be on PATH, or use absolute paths)
add bear-notes -- "$HOME/anaconda/bin/python3" "$HOME/Projects/haak-world/bear-mcp/mcp_server.py"
add tasks      -- haak-tasks
add stitch     -- stitch-mcp

# HTTP server (shared local endpoint)
claude mcp remove google-workspace --scope user >/dev/null 2>&1 || true
claude mcp add --transport http google-workspace http://localhost:8200/mcp --scope user

echo "User-scope MCP servers registered. Verify with: claude mcp list"
