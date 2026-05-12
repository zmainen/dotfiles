# Dotfiles

Personal configuration for macOS (Zsh, Git, Conda, Claude Code).

## What's here

| File | What it does |
|:-----|:-------------|
| `.zshrc` | Zsh config — Oh My Zsh, paths, Conda init |
| `.gitconfig` | Git defaults (template: `.gitconfig.template`) |
| `shell_aliases` | Shell aliases — sourced from `.zshrc` as `~/.shell_aliases` |
| `claude-provider.sh` | Switch Claude Code between Max, Vertex, and API backends |
| `clean-secrets.py` | Manage `~/.secrets` — lint, format, add/remove, deduplicate |
| `conda_auto_env.zsh` | Auto-activate Conda envs when entering directories |
| `.secrets.template` | Skeleton for `~/.secrets` (no actual keys) |

## Setup

```bash
git clone https://github.com/zmainen/dotfiles.git ~/Projects/dotfiles

# symlink what you need
ln -sf ~/Projects/dotfiles/.zshrc ~/.zshrc
ln -sf ~/Projects/dotfiles/shell_aliases ~/.shell_aliases

# create your secrets file from the template
cp ~/Projects/dotfiles/.secrets.template ~/.secrets
chmod 600 ~/.secrets
# fill in actual keys with your editor, or:
# secrets set OPENAI_API_KEY "sk-..."
```

## `secrets` CLI

A Click-based tool for managing sourced shell secrets files (`~/.secrets` or any `export`-based file). Aliased as `secrets` via `shell_aliases`.

```
secrets                      # preview cleaned + sorted output
secrets apply                # write (creates timestamped .bak)
secrets diff                 # unified diff of what would change
secrets lint                 # syntax errors, bad quoting, bare assignments
secrets list                 # groups + variable names (no values)
secrets grep <pattern>       # find variables by name substring
secrets set KEY "value"      # add or update a secret
secrets rm KEY               # remove a secret
secrets dupes                # show duplicates and value conflicts
secrets dupes --fix          # resolve interactively
secrets check                # exit 1 if file needs cleaning
secrets -f .env lint         # works on any export-based file
```

**What `lint` catches:** missing `export` keyword, malformed exports, unmatched quotes, unquoted values with spaces, empty values, `unset` lines, duplicate and conflicting exports, unrecognised lines.

**What `apply` does:** groups exports by prefix, sorts groups alphabetically, aligns `=` signs within groups, deduplicates (last wins), normalizes blank lines. Always creates a backup first.

**Safety:** every mutation (`apply`, `set`, `rm`, `dupes --fix`) creates a timestamped `.bak` with `chmod 600` before writing. The `.gitignore` excludes `.secrets`, `.secrets.*`, `.env`, `.env.*`, `*.key`, and `*.pem`.

Requires: Python 3.9+, [Click](https://click.palletsprojects.com/) (`pip install click`).

## `claude-provider`

Switch Claude Code between subscription, Vertex AI, and direct API backends. See header comments in `claude-provider.sh` for usage.

## Security

`~/.secrets` is **never committed** — blocked by `.gitignore`. The `.secrets.template` shows structure without values. Backups (`.secrets.*.bak`) are also gitignored.
