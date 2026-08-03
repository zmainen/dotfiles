#!/usr/bin/env zsh

# --- Homebrew ---
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# --- Oh My Zsh ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="ys"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# --- Machine identity ---
export HAAK_MACHINE="mac"
export HAAK_ROOT="$HOME/Projects/haak"

# --- Secrets ---
# Values live in the macOS Keychain (migrated 2026-05-24). `secrets export`
# emits the curated shell_env set from Keychain — the replacement for the old
# `source ~/.secrets`. See infra/credentials/2026-05-29-secrets-env-migration-rfc.md
eval "$("$HOME/Projects/secrets-cli/secrets" export 2>/dev/null)"

# --- Agent identity ---
# HAAK_AGENT_TOKEN is the per-agent MCP credential. .mcp.json uses it.
# Default: shared MCP_AUTH_TOKEN (unverified identity — audit mode allows it).
# Per-agent override: `claude-agent <name>` reads the real credential from Keychain.
export HAAK_AGENT_TOKEN="${HAAK_AGENT_TOKEN:-$MCP_AUTH_TOKEN}"

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
export PATH="$HOME/github/signal-cli/:$PATH"
export PATH="/Applications/NEURON/bin:$PATH"
export PATH="$(brew --prefix hdf5)/bin:$PATH"
export PATH="$(brew --prefix ffmpeg)/bin:$PATH"

# --- PYTHONPATH ---
export PYTHONPATH="/Applications/NEURON/lib/python:$PYTHONPATH"
export PYTHONPATH="$HOME/python/lunar_tools:$HOME/python/lunar_tools/lunar_tools:$PYTHONPATH"

# --- Display ---
export DISPLAY=:0

# --- Prompt ---
export CONDA_CHANGEPS1=false
export VIRTUAL_ENV_DISABLE_PROMPT=1
RPROMPT='${CONDA_DEFAULT_ENV:+🐍 $CONDA_DEFAULT_ENV}'

# --- Aliases ---
alias exa='eza'
[ -f ~/.shell_aliases ] && source ~/.shell_aliases

# --- Conda ---
[ -f "/Users/zach/anaconda/etc/profile.d/conda.sh" ] && . "/Users/zach/anaconda/etc/profile.d/conda.sh"
[ -f "$HOME/Projects/zmainen/dotfiles/conda_auto_env.zsh" ] && . "$HOME/Projects/zmainen/dotfiles/conda_auto_env.zsh" 2>/dev/null

# --- filen-cli ---
export PATH="$PATH:$HOME/.filen-cli/bin"

# --- Google Cloud SDK ---
export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3
if [ -f "$HOME/Library/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Library/google-cloud-sdk/path.zsh.inc"; fi

# --- audio-bridge ---
abs() {
  conda activate "audio" >/dev/null 2>&1 || return $?
  python -m audio_bridge.tools.abs "$@"
}

# Claude Code provider switching (max | vertex | apikey)
source ~/Projects/zmainen/dotfiles/claude-provider.sh

# --- ZED ---
export DISABLE_AUTO_TITLE=true
export FLYCTL_INSTALL="$HOME/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
