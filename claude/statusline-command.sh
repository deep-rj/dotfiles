#!/bin/bash
# Status line converted from ~/.bashrc's colored PS1:
#   PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
# Extended with model name and width-aware path shrinking.
input=$(cat)
dir=$(echo "$input" | grep -o '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
model=$(echo "$input" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
user=$(whoami)
host=$(hostname -s)

# Collapse $HOME to ~ (the tilde must be escaped: bash tilde-expands an
# unescaped ~ in the replacement text back into $HOME, silently undoing this).
dir="${dir/#$HOME/\~}"

# Shrink a path to fit within $budget columns: first collapse middle
# segments to their initial letter, then drop them entirely, then as a
# last resort trim the final segment itself. Always keeps a leading ~
# (or /) and the last segment intact as long as possible, since those
# carry the most information about "where am I".
shrink_path() {
  local path="$1" budget="$2"
  (( ${#path} <= budget )) && { printf '%s' "$path"; return; }

  local prefix="" rest="$path"
  if [[ "$rest" == "~"* ]]; then
    prefix="~"
    rest="${rest#\~}"
  fi
  rest="${rest#/}"

  IFS='/' read -ra parts <<< "$rest"
  local n=${#parts[@]}
  (( n == 0 )) && { printf '%s' "$path"; return; }
  local last="${parts[$((n-1))]}"

  # Step 1: collapse middle segments to their first letter.
  local shrunk="$prefix" i
  for (( i=0; i<n-1; i++ )); do
    shrunk+="/${parts[$i]:0:1}"
  done
  shrunk+="/${last}"
  (( ${#shrunk} <= budget )) && { printf '%s' "$shrunk"; return; }

  # Step 2: still too long, drop the middle segments entirely.
  local collapsed="${prefix}/…/${last}"
  (( ${#collapsed} <= budget )) && { printf '%s' "$collapsed"; return; }

  # Step 3: still too long, trim the last segment itself from the left.
  local avail=$(( budget - ${#prefix} - 4 ))
  (( avail < 1 )) && avail=1
  printf '%s/…/…%s' "$prefix" "${last:0-avail}"
}

cols=${COLUMNS:-80}
fixed="${user}@${host}: [${model}]"
budget=$(( cols - ${#fixed} - 1 ))
(( budget < 8 )) && budget=8
dir=$(shrink_path "$dir" "$budget")

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m \033[02m[%s]\033[00m' "$user" "$host" "$dir" "$model"
