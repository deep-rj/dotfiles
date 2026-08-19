#!/bin/bash
# Status line converted from ~/.bashrc's colored PS1:
#   PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
# Extended with model name.
input=$(cat)
dir=$(echo "$input" | grep -o '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
model=$(echo "$input" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
user=$(whoami)
host=$(hostname -s)

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m \033[02m[%s]\033[00m' "$user" "$host" "$dir" "$model"
