#!/usr/bin/env bash
# Idempotent bootstrap: safe to re-run on any machine (fresh pod or laptop).
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backed up existing $dest"
  fi
  ln -s "$src" "$dest"
  echo "Linked $dest -> $src"
}

clone_if_missing() {
  local repo="$1" dest="$2"
  if [ ! -d "$dest" ]; then
    git clone --depth=1 "$repo" "$dest"
  fi
}

echo "== Oh My Zsh + plugins/theme =="
clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
clone_if_missing https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_if_missing https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"

echo "== Symlinking config =="
link "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
link "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
link "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"
link "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
link "$DOTFILES_DIR/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

echo "== Merging Claude Code statusLine into ~/.claude/settings.json =="
python3 - "$DOTFILES_DIR/claude/settings.snippet.json" "$HOME/.claude/settings.json" <<'EOF'
import json, sys, os

snippet_path, settings_path = sys.argv[1], sys.argv[2]
with open(snippet_path) as f:
    snippet = json.load(f)

settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)

settings.update(snippet)

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
EOF

echo "Done. Start a new shell (or 'exec zsh') to pick up the changes."
