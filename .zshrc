#!/usr/bin/env zsh
# Clean ZSH Configuration

# Suppress conda and virtual env prompt changes
export CONDA_CHANGEPS1=false
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="ys"

# Plugins
plugins=(git)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# User configuration

# Fix issues with exa
alias exa='eza'

# Load secure API keys (never commit this file!)
if [ -f ~/.secrets ]; then
    source ~/.secrets
fi

# PATH additions
export PATH="$HOME/github/signal-cli/:$PATH"
export PATH="/Applications/NEURON/bin":$PATH
export PATH="/opt/homebrew/Cellar/hdf5/1.14.3:$PATH"
export PATH="/opt/homebrew/Cellar/ffmpeg/6.0_2:$PATH"

# PYTHONPATH
export PYTHONPATH="/Applications/NEURON/lib/python":$PYTHONPATH
export PYTHONPATH="$HOME/python/lunar_tools:$HOME/python/lunar_tools/lunar_tools":$PYTHONPATH

# Display for Quartz
export DISPLAY=:0

# Load shell aliases (suppress any output)
[ -f "$HOME/.shell_aliases/cli.sh" ] && source "$HOME/.shell_aliases/cli.sh" 2>/dev/null
[ -f "$HOME/.shell_aliases/other.sh" ] && source "$HOME/.shell_aliases/other.sh" 2>/dev/null
[ -f "$HOME/.shell_aliases/tmux.sh" ] && source "$HOME/.shell_aliases/tmux.sh" 2>/dev/null

# Conda auto-env (with output suppression)
if [ -f "$HOME/.scripts/conda_auto_env.zsh" ]; then
    # Temporarily redirect stderr to suppress any warnings
    exec 3>&2 2>/dev/null
    source "$HOME/.scripts/conda_auto_env.zsh"
    exec 2>&3
fi

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/zach/anaconda/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/zach/anaconda/etc/profile.d/conda.sh" ]; then
        . "/Users/zach/anaconda/etc/profile.d/conda.sh"
    else
        export PATH="/Users/zach/anaconda/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Suppress conda activation messages
conda config --set changeps1 false 2>/dev/null

# Add any custom configurations below this line