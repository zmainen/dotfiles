# claude — personal Claude Code config

Portable Claude Code skills + MCP registrations, promoted out of the HAAK repo
so they work in **any** project, not just `~/Projects/haak`.

## Contents

- `skills/` — global skills (symlinked into `~/.claude/skills/` by `install.sh`)
  - `note` — quick capture to Bear (needs the `bear-notes` MCP)
  - `eject` — eject external macOS drives (pure `diskutil`, no deps)
  - `calendar` — read the macOS system calendar (`calendar.swift`, EventKit)
- `setup-user-mcp.sh` — registers user-scope MCP servers in `~/.claude.json`
- `install.sh` — symlinks the skills + runs the MCP setup

## Why not commit `~/.claude.json`?

It's large, mode-600, and mixes MCP config with per-project session history
(and possibly tokens). We keep the *declarative* MCP setup here as a script
instead, and let `~/.claude.json` stay machine-local.

## Install on a new machine

```bash
bash ~/Projects/zmainen/dotfiles/claude/install.sh
```

## Promoted MCP servers

| Server | Kind | Notes |
|:-------|:-----|:------|
| `bear-notes` | stdio | `bear-mcp/mcp_server.py` (lives in `haak-world/`) |
| `tasks` | stdio | `haak-tasks` — to-do ↔ Apple Reminders |
| `stitch` | stdio | `stitch-mcp` — Claude Code session transcript tools |
| `google-workspace` | http | `localhost:8200/mcp` — Gmail/Drive/Calendar/Docs (per-account OAuth) |

These commands must be on `PATH` (or absolute) when Claude Code launches.
