#!/usr/bin/env bash
# Idempotent bootstrap: safe to re-run on any machine (fresh pod or laptop).
# Always previews what would change before touching anything. Prompts for
# confirmation when run interactively and there's something to do; use
# --yes to skip the prompt (e.g. unattended pod provisioning) or --dry-run
# to only preview.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"

# Path a clobbered dest would be moved to under BACKUP_DIR, preserving its
# position relative to $HOME so multiple files from one run land together.
backup_rel() {
  case "$1" in
    "$HOME"/*) echo "${1#"$HOME"/}" ;;
    /*) echo "${1#/}" ;;
    *) echo "$1" ;;
  esac
}

DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -y|--yes) ASSUME_YES=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

CLONES=(
  "https://github.com/ohmyzsh/ohmyzsh.git|$HOME/.oh-my-zsh"
  "https://github.com/zsh-users/zsh-autosuggestions|$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  "https://github.com/zsh-users/zsh-syntax-highlighting|$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  "https://github.com/romkatv/powerlevel10k.git|$ZSH_CUSTOM/themes/powerlevel10k"
)
LINKS=(
  "$DOTFILES_DIR/zsh/.zshrc|$HOME/.zshrc"
  "$DOTFILES_DIR/zsh/.p10k.zsh|$HOME/.p10k.zsh"
  "$DOTFILES_DIR/bash/.bashrc|$HOME/.bashrc"
  "$DOTFILES_DIR/git/.gitconfig|$HOME/.gitconfig"
  "$DOTFILES_DIR/claude/statusline-command.sh|$HOME/.claude/statusline-command.sh"
  "$DOTFILES_DIR/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md"
)
SETTINGS_SNIPPET="$DOTFILES_DIR/claude/settings.snippet.json"
SETTINGS_FILE="$HOME/.claude/settings.json"

any_changes=false

echo "== Plan =="

for entry in "${CLONES[@]}"; do
  dest="${entry#*|}"
  if [ ! -d "$dest" ]; then
    echo "  + clone $dest"
    any_changes=true
  fi
done

for entry in "${LINKS[@]}"; do
  src="${entry%%|*}"
  dest="${entry#*|}"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    continue
  fi
  any_changes=true
  if [ ! -e "$dest" ]; then
    echo "  + link $dest -> $src (new)"
  elif diff -q "$src" "$dest" >/dev/null 2>&1; then
    echo "  + link $dest -> $src (identical content, replacing plain file with symlink)"
  else
    echo "  + link $dest -> $src, backing up existing file to $BACKUP_DIR/$(backup_rel "$dest") first:"
    diff -u "$dest" "$src" | sed 's/^/      /' || true
  fi
done

echo "  -- settings.json --"
settings_exit=0
settings_output=$(python3 "$DOTFILES_DIR/claude/merge_settings.py" "$SETTINGS_SNIPPET" "$SETTINGS_FILE" 2>&1) || settings_exit=$?
echo "$settings_output" | sed 's/^/  /'
if [ "$settings_exit" != "0" ]; then
  echo "  (conflicts above are left as-is; reconcile settings.snippet.json manually if you want dotfiles to own them)"
fi
if echo "$settings_output" | grep -qE '^\s*\+ (add|update)'; then
  any_changes=true
fi

if ! $any_changes; then
  if [ "$settings_exit" != "0" ]; then
    echo "Nothing to apply, but see the conflict above."
  else
    echo "Already up to date."
  fi
  exit 0
fi

if $DRY_RUN; then
  echo "Dry run - no changes made."
  exit 0
fi

if ! $ASSUME_YES && [ -t 0 ] && [ -t 1 ]; then
  read -r -p "Apply the changes above? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo "== Applying =="

for entry in "${CLONES[@]}"; do
  repo="${entry%%|*}"
  dest="${entry#*|}"
  if [ ! -d "$dest" ]; then
    git clone --depth=1 "$repo" "$dest"
  fi
done

link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup_dest="$BACKUP_DIR/$(backup_rel "$dest")"
    mkdir -p "$(dirname "$backup_dest")"
    mv "$dest" "$backup_dest"
    echo "Backed up existing $dest -> $backup_dest"
  fi
  ln -s "$src" "$dest"
  echo "Linked $dest -> $src"
}
for entry in "${LINKS[@]}"; do
  link "${entry%%|*}" "${entry#*|}"
done

echo "Merging Claude Code settings.json..."
python3 "$DOTFILES_DIR/claude/merge_settings.py" "$SETTINGS_SNIPPET" "$SETTINGS_FILE" --apply || true

echo "Done. Start a new shell (or 'exec zsh') to pick up the changes."
