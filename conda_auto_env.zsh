#!/usr/bin/env zsh
# Automatic conda environment activation based on .python-version or environment.yml

conda_auto_env() {
    if [[ -f ".python-version" ]]; then
        # Read the environment name from .python-version
        local env_name=$(cat .python-version)
        
        # Check if we're not already in this environment
        if [[ "$CONDA_DEFAULT_ENV" != "$env_name" ]]; then
            # Check if conda is available
            if ! command -v conda &> /dev/null; then
                return
            fi
            
            # Check if the environment exists
            if conda env list 2>/dev/null | grep -q "^$env_name "; then
                conda activate "$env_name" 2>/dev/null
            fi
        fi
    elif [[ -f "environment.yml" ]]; then
        # Extract environment name from environment.yml
        local env_name=$(grep "^name:" environment.yml | cut -d' ' -f2)
        
        if [[ -n "$env_name" ]] && [[ "$CONDA_DEFAULT_ENV" != "$env_name" ]]; then
            # Check if conda is available
            if ! command -v conda &> /dev/null; then
                return
            fi
            
            if conda env list 2>/dev/null | grep -q "^$env_name "; then
                conda activate "$env_name" 2>/dev/null
            fi
        fi
    elif [[ -n "$CONDA_DEFAULT_ENV" ]] && [[ "$CONDA_DEFAULT_ENV" != "base" ]]; then
        # Only deactivate if we're leaving ALL project directories
        local in_project=false
        local current_dir="$PWD"
        while [[ "$current_dir" != "/" ]]; do
            if [[ -f "$current_dir/.python-version" ]] || [[ -f "$current_dir/environment.yml" ]]; then
                in_project=true
                break
            fi
            current_dir=$(dirname "$current_dir")
        done
        
        if [[ "$in_project" == "false" ]] && command -v conda &> /dev/null; then
            conda deactivate 2>/dev/null
        fi
    fi
}

# Hook into directory changes
autoload -U add-zsh-hook
add-zsh-hook chpwd conda_auto_env

# Run on shell startup for current directory
conda_auto_env