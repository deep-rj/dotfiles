#!/usr/bin/env bash
# Idempotent bootstrap: safe to re-run on any machine (fresh pod or laptop).
# Always previews what would change before touching anything. Prompts for
# confirmation when run interactively and there's something to do; use
# --yes to skip the prompt (e.g. unattended pod provisioning) or --dry-run
# to only preview. --profile NAME links profiles/NAME/ (machine-specific
# config) into ~/.config/dotfiles/profile.d/; without it the profile already
# installed is kept, else "default" (no profile). A profile's
# install-options.sh can move $HOME paths onto persistent storage (symlinked
# back) and opt in to installing Claude Code when it's missing.
set -euo pipefail

for cmd in git python3 jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "install.sh needs '$cmd' on PATH - see README.md#prerequisites." >&2
    exit 1
  fi
done

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
PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -y|--yes) ASSUME_YES=true ;;
    --profile=*) PROFILE="${1#--profile=}" ;;
    --profile)
      [ $# -ge 2 ] || { echo "--profile needs a name" >&2; exit 1; }
      PROFILE="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

PROFILE_LINK_DIR="$HOME/.config/dotfiles/profile.d"
PROFILE_FILES=(bashrc.sh zshrc.sh gitconfig)

# True for a symlink that this script created from a profile.
is_profile_link() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in
    "$DOTFILES_DIR"/profiles/*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -z "$PROFILE" ]; then
  PROFILE=default
  for f in "${PROFILE_FILES[@]}"; do
    if is_profile_link "$PROFILE_LINK_DIR/$f"; then
      target="$(readlink "$PROFILE_LINK_DIR/$f")"
      target="${target#"$DOTFILES_DIR"/profiles/}"
      PROFILE="${target%%/*}"
      break
    fi
  done
fi

if [ "$PROFILE" != default ] && [ ! -d "$DOTFILES_DIR/profiles/$PROFILE" ]; then
  echo "Unknown profile '$PROFILE'. Available: default $(cd "$DOTFILES_DIR/profiles" && echo *)" >&2
  exit 1
fi

PERSIST_DIR=""
PERSIST_PATHS=()
PERSIST_SKIPPED=""
INSTALL_CLAUDE=false
if [ "$PROFILE" != default ] && [ -f "$DOTFILES_DIR/profiles/$PROFILE/install-options.sh" ]; then
  . "$DOTFILES_DIR/profiles/$PROFILE/install-options.sh"
  # A missing parent means the volume isn't mounted; creating it would put
  # "persistent" state on ephemeral disk.
  if [ ! -d "$(dirname "$PERSIST_DIR")" ]; then
    PERSIST_SKIPPED="$(dirname "$PERSIST_DIR")"
    PERSIST_PATHS=()
  fi
fi

# Where $1 resolves once PERSIST_PATHS are linked into PERSIST_DIR. Until a
# path's store exists, its local copy is what gets moved there, so it stays.
persisted_path() {
  local p
  for p in ${PERSIST_PATHS[@]+"${PERSIST_PATHS[@]}"}; do
    p="${p%/}"
    [ -e "$PERSIST_DIR/$p" ] || continue
    case "$1" in
      "$HOME/$p"|"$HOME/$p"/*) echo "$PERSIST_DIR/${1#"$HOME"/}"; return ;;
    esac
  done
  echo "$1"
}

if command -v zsh >/dev/null 2>&1; then
  HAS_ZSH=true
else
  HAS_ZSH=false
fi

# Only used when HAS_ZSH; loops over it are guarded rather than emptying it,
# since "${arr[@]}" on an empty array trips set -u in bash 3.2 (macOS).
CLONES=(
  "https://github.com/ohmyzsh/ohmyzsh.git|$HOME/.oh-my-zsh"
  "https://github.com/zsh-users/zsh-autosuggestions|$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  "https://github.com/zsh-users/zsh-syntax-highlighting|$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  "https://github.com/romkatv/powerlevel10k.git|$ZSH_CUSTOM/themes/powerlevel10k"
)
LINKS=(
  "$DOTFILES_DIR/bash/.bashrc|$HOME/.bashrc"
  "$DOTFILES_DIR/git/.gitconfig|$HOME/.gitconfig"
  "$DOTFILES_DIR/claude/statusline-command.sh|$HOME/.claude/statusline-command.sh"
  "$DOTFILES_DIR/claude/hooks/format-on-edit.sh|$HOME/.claude/hooks/format-on-edit.sh"
  "$DOTFILES_DIR/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md"
  "$DOTFILES_DIR/claude/skills/extract-public-repo|$HOME/.claude/skills/extract-public-repo"
)
if $HAS_ZSH; then
  LINKS=(
    "$DOTFILES_DIR/zsh/.zshrc|$HOME/.zshrc"
    "$DOTFILES_DIR/zsh/.p10k.zsh|$HOME/.p10k.zsh"
    "${LINKS[@]}"
  )
fi
STALE=()
for f in "${PROFILE_FILES[@]}"; do
  dest="$PROFILE_LINK_DIR/$f"
  src="$DOTFILES_DIR/profiles/$PROFILE/$f"
  if [ "$PROFILE" != default ] && [ -f "$src" ]; then
    LINKS+=("$src|$dest")
  elif is_profile_link "$dest"; then
    STALE+=("$dest")
  fi
done
SETTINGS_SNIPPET="$DOTFILES_DIR/claude/settings.snippet.json"
SETTINGS_FILE="$HOME/.claude/settings.json"

any_changes=false

echo "== Plan =="
echo "  profile: $PROFILE"

if [ -n "$PERSIST_SKIPPED" ]; then
  echo "  - $PERSIST_SKIPPED not found: skipping persistent paths (re-run once it's mounted)"
fi
for entry in ${PERSIST_PATHS[@]+"${PERSIST_PATHS[@]}"}; do
  dest="$HOME/${entry%/}"
  store="$PERSIST_DIR/${entry%/}"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$store" ]; then
    continue
  fi
  any_changes=true
  if [ ! -e "$store" ] && [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "  + persist $dest: move to $store and link back"
  elif [ ! -e "$store" ]; then
    echo "  + persist $dest: link to $store (new)"
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  + persist $dest: link to existing $store, backing up local copy to $BACKUP_DIR/$(backup_rel "$dest") first"
  else
    echo "  + persist $dest: link to existing $store"
  fi
done

if $HAS_ZSH; then
  for entry in "${CLONES[@]}"; do
    dest="${entry#*|}"
    if [ ! -d "$dest" ]; then
      echo "  + clone $dest"
      any_changes=true
    fi
  done
else
  echo "  - zsh not found: skipping Oh My Zsh, its plugins/theme, .zshrc and .p10k.zsh (re-run after installing zsh)"
fi

NEED_CLAUDE=false
if $INSTALL_CLAUDE && ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  if command -v curl >/dev/null 2>&1; then
    echo "  + install Claude Code (official native installer)"
    NEED_CLAUDE=true
    any_changes=true
  else
    echo "  - curl not found: skipping Claude Code install (re-run after installing curl)"
  fi
fi

for entry in "${LINKS[@]}"; do
  src="${entry%%|*}"
  dest="${entry#*|}"
  current="$(persisted_path "$dest")"
  if [ -L "$current" ] && [ "$(readlink "$current")" = "$src" ]; then
    continue
  fi
  any_changes=true
  if [ ! -e "$current" ]; then
    echo "  + link $dest -> $src (new)"
  elif is_profile_link "$current"; then
    echo "  + relink $dest -> $src (was $(readlink "$current"))"
  elif diff -q "$src" "$current" >/dev/null 2>&1; then
    echo "  + link $dest -> $src (identical content, replacing plain file with symlink)"
  else
    echo "  + link $dest -> $src, backing up existing file to $BACKUP_DIR/$(backup_rel "$dest") first:"
    diff -u "$current" "$src" | sed 's/^/      /' || true
  fi
done

for dest in ${STALE[@]+"${STALE[@]}"}; do
  echo "  - unlink $dest (profile link, not in profile '$PROFILE')"
  any_changes=true
done

echo "  -- settings.json --"
settings_exit=0
settings_output=$(python3 "$DOTFILES_DIR/claude/merge_settings.py" "$SETTINGS_SNIPPET" "$(persisted_path "$SETTINGS_FILE")" 2>&1) || settings_exit=$?
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

backup() {
  local backup_dest="$BACKUP_DIR/$(backup_rel "$1")"
  mkdir -p "$(dirname "$backup_dest")"
  mv "$1" "$backup_dest"
  echo "Backed up existing $1 -> $backup_dest"
}

# Entries ending in / are directories, created if missing; a missing file is
# left for its owner to create through the symlink.
persist() {
  local entry="$1"
  local dest="$HOME/${entry%/}" store="$PERSIST_DIR/${entry%/}"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$store" ]; then
    return
  fi
  mkdir -p "$(dirname "$store")" "$(dirname "$dest")"
  if [ ! -e "$store" ] && [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$store"
    echo "Moved $dest -> $store"
  else
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      backup "$dest"
    fi
    if [ "$entry" != "${entry%/}" ]; then
      mkdir -p "$store"
    fi
  fi
  ln -s "$store" "$dest"
  echo "Linked $dest -> $store"
}
if [ ${#PERSIST_PATHS[@]} -gt 0 ]; then
  # Private because persisted state includes credentials.
  (umask 077 && mkdir -p "$PERSIST_DIR")
fi
for entry in ${PERSIST_PATHS[@]+"${PERSIST_PATHS[@]}"}; do
  persist "$entry"
done

if $HAS_ZSH; then
  for entry in "${CLONES[@]}"; do
    repo="${entry%%|*}"
    dest="${entry#*|}"
    if [ ! -d "$dest" ]; then
      git clone --depth=1 "$repo" "$dest"
    fi
  done
fi

link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if is_profile_link "$dest"; then
    rm "$dest"
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    backup "$dest"
  fi
  ln -s "$src" "$dest"
  echo "Linked $dest -> $src"
}
for entry in "${LINKS[@]}"; do
  link "${entry%%|*}" "${entry#*|}"
done

for dest in ${STALE[@]+"${STALE[@]}"}; do
  rm "$dest"
  echo "Unlinked $dest"
done

if $NEED_CLAUDE; then
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash ||
    echo "Claude Code install failed; re-run install.sh to retry." >&2
fi

echo "Merging Claude Code settings.json..."
python3 "$DOTFILES_DIR/claude/merge_settings.py" "$SETTINGS_SNIPPET" "$SETTINGS_FILE" --apply || true

if $HAS_ZSH; then
  echo "Done. Start a new shell (or 'exec zsh') to pick up the changes."
else
  echo "Done. Start a new shell (or 'exec bash') to pick up the changes."
fi
