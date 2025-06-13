# Zach's Dotfiles

Personal configuration files for macOS development environment.

## Structure

- `.zshrc` - Zsh configuration
- `.gitconfig` - Git configuration
- `.aliases` - Shell aliases
- `bin/` - Personal scripts
- `config/` - Application configurations

## Security

**NEVER commit `.secrets` file!** It contains API keys and sensitive data.

## Installation

```bash
# Clone the repository
git clone https://github.com/zmainen/dotfiles.git ~/dotfiles

# Create symlinks
ln -sf ~/dotfiles/.zshrc ~/.zshrc
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.aliases ~/.aliases

# Copy secrets template and fill in your keys
cp ~/dotfiles/.secrets.template ~/.secrets
# Edit ~/.secrets with your actual API keys
```

## Secrets Template

The `.secrets.template` file shows the structure without actual keys.