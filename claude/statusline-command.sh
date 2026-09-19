#!/bin/bash
# Palette and segment style follow the Powerlevel10k lean prompt in zsh/.p10k.zsh.
# Written for bash 3.2 (macOS /bin/bash): no \u escapes, glyph widths tracked as integers.
# Slicing of paths and branch names assumes a UTF-8 locale.
input=$(cat)
{
  IFS= read -r dir
  IFS= read -r model
  IFS= read -r ctx_pct
  IFS= read -r effort
  IFS= read -r worktree
  IFS= read -r repo_url
  # Every scalar above emits exactly one line; the variable-length array must stay last.
  extra_dirs=()
  while IFS= read -r extra; do
    [[ -n $extra ]] && extra_dirs+=("$extra")
  done
} < <(jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.context_window.used_percentage | if . == null then "" else floor end),
  (.effort.level // ""),
  (.workspace.git_worktree | if type == "string" then . else "" end),
  (.workspace.repo | if type == "object" and ([.host, .owner, .name] | all(type == "string")) then "https://\(.host | ascii_downcase)/\(.owner)/\(.name)" else "" end),
  ((.workspace.added_dirs // [])[]?)
' <<<"$input")
repo_dir="$dir"
worktree="${worktree##*/}"
# The URL is embedded in an escape sequence, so control characters could break out of it.
[[ $repo_url =~ [[:cntrl:]] ]] && repo_url=""

RESET=$'\033[0m'
BOLD=$'\033[1m'
C_CONTEXT=$'\033[38;5;180m'
C_ROOT=$'\033[1;38;5;178m'
C_DIR=$'\033[38;5;31m'
C_ANCHOR=$'\033[38;5;39m'
C_CLEAN=$'\033[38;5;76m'
C_MODIFIED=$'\033[38;5;178m'
C_UNTRACKED=$'\033[38;5;39m'
C_CONFLICT=$'\033[38;5;196m'
C_CRITICAL=$'\033[38;5;160m'
C_MUTED=$'\033[38;5;244m'
C_BAR_EMPTY=$'\033[38;5;240m'

BRANCH_ICON=$'\xef\x84\xa6'
BAR_WIDTH=8

# Collapse $HOME to ~ only at a path boundary, so /home/user-old stays intact.
# Result is returned in REPLY; a command substitution would fork.
collapse_home() {
  REPLY=$1
  [[ -n $HOME && ( $1 == "$HOME" || $1 == "$HOME"/* ) ]] && REPLY="~${1#"$HOME"}"
}
collapse_home "$dir"
dir=$REPLY

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

# Segment widths are tracked as integers because ${#str} counts bytes, not
# columns, when the locale isn't UTF-8.
git_colored="" git_w=0
git_add() {
  git_colored+=" $1$2$3"
  git_w=$(( git_w + 2 + ${#3} ))
}

git_segment() {
  local porcelain head oid ahead behind staged modified untracked conflicted label repo_host remote_icon link_open="" link_close=""
  # --no-optional-locks: don't contend for index.lock with git commands Claude runs.
  porcelain=$(git --no-optional-locks -C "$1" status --porcelain=v2 --branch 2>/dev/null) || return
  read -r head oid ahead behind staged modified untracked conflicted < <(awk '
    /^# branch.oid/  { oid = substr($3, 1, 8) }
    /^# branch.head/ { head = $3 }
    /^# branch.ab/   { ahead = substr($3, 2); behind = substr($4, 2) }
    /^[12] /         { if (substr($2, 1, 1) != ".") staged++; if (substr($2, 2, 1) != ".") modified++ }
    /^u /            { conflicted++ }
    /^\? /           { untracked++ }
    END { print head, oid, ahead + 0, behind + 0, staged + 0, modified + 0, untracked + 0, conflicted + 0 }
  ' <<<"$porcelain")

  if [[ $head == "(detached)" ]]; then
    label="@$oid"
  else
    label="$head"
    (( ${#label} > 32 )) && label="${label:0:12}…${label:0-12}"
  fi
  if [[ -n $repo_url ]]; then
    link_open=$'\033]8;;'"${repo_url}"$'\033\\'
    link_close=$'\033]8;;\033\\'
  fi

  # Same icons and domain matching as p10k's VCS_GIT_REMOTE_ICONS in nerdfont-v3 mode;
  # any other remote, or none, gets the generic git icon.
  repo_host="${repo_url#https://}"
  repo_host="${repo_host%%/*}"
  case $repo_host in
    github.com|*.github.com) remote_icon=$'\xef\x84\x93' ;;
    gitlab.com|*.gitlab.com) remote_icon=$'\xef\x8a\x96' ;;
    bitbucket.org|*.bitbucket.org) remote_icon=$'\xee\x9c\x83' ;;
    dev.azure.com|*.dev.azure.com|visualstudio.com|*.visualstudio.com) remote_icon=$'\xee\xaf\xa8' ;;
    *) remote_icon=$'\xef\x87\x93' ;;
  esac

  git_colored="${C_CLEAN}${link_open}${remote_icon} ${BRANCH_ICON} ${label}${link_close}"
  git_w=$(( 4 + ${#label} ))

  (( ahead ))      && git_add "$C_CLEAN" "⇡" "$ahead"
  (( behind ))     && git_add "$C_CLEAN" "⇣" "$behind"
  (( conflicted )) && git_add "$C_CONFLICT" "~" "$conflicted"
  (( staged ))     && git_add "$C_CLEAN" "+" "$staged"
  (( modified ))   && git_add "$C_MODIFIED" "!" "$modified"
  (( untracked ))  && git_add "$C_UNTRACKED" "?" "$untracked"
}

ctx_colored="" ctx_w=0
ctx_segment() {
  [[ -n $ctx_pct ]] || return
  local color=$C_CLEAN filled=$(( (ctx_pct * BAR_WIDTH + 50) / 100 )) i on="" off=""
  if (( ctx_pct >= 90 )); then
    color=$C_CRITICAL
  elif (( ctx_pct >= 70 )); then
    color=$C_MODIFIED
  fi
  (( filled > BAR_WIDTH )) && filled=$BAR_WIDTH
  for (( i=0; i<BAR_WIDTH; i++ )); do
    if (( i < filled )); then on+="█"; else off+="░"; fi
  done
  ctx_colored="${color}${on}${C_BAR_EMPTY}${off}${color} ${ctx_pct}%"
  ctx_w=$(( BAR_WIDTH + 2 + ${#ctx_pct} ))
}

git_segment "$repo_dir"
ctx_segment

# Like p10k's context segment: shown only as root or over SSH.
user_host="" c_user_host=$C_CONTEXT
if (( EUID == 0 )); then
  user_host="$(whoami)@$(hostname -s)" c_user_host=$C_ROOT
elif [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]]; then
  user_host="$(whoami)@$(hostname -s)"
fi

cols=${COLUMNS:-80}
[[ -n $model ]] || effort=""
# Drop the least useful segments (effort, worktree tag, model, then user@host)
# until the path gets a workable share of the width.
while :; do
  fixed=0
  [[ -n $model ]] && fixed=$(( fixed + 1 + ${#model} ))
  [[ -n $effort ]] && fixed=$(( fixed + 1 + ${#effort} ))
  [[ -n $worktree ]] && fixed=$(( fixed + 4 + ${#worktree} ))
  [[ -n $user_host ]] && fixed=$(( fixed + ${#user_host} + 1 ))
  (( git_w )) && fixed=$(( fixed + 1 + git_w ))
  (( ctx_w )) && fixed=$(( fixed + 1 + ctx_w ))
  budget=$(( cols - fixed - 2 ))
  (( budget >= 12 )) && break
  if [[ -n $effort ]]; then effort=""
  elif [[ -n $worktree ]]; then worktree=""
  elif [[ -n $model ]]; then model=""
  elif [[ -n $user_host ]]; then user_host=""
  else break; fi
done
(( budget < 8 )) && budget=8
dir=$(shrink_path "$dir" "$budget")

dir_head="" dir_last="$dir"
if [[ $dir == */* ]]; then
  dir_head="${dir%/*}/"
  dir_last="${dir##*/}"
fi

line=""
[[ -n $user_host ]] && line+="${c_user_host}${user_host}${RESET} "
line+="${C_DIR}${dir_head}${BOLD}${C_ANCHOR}${dir_last}${RESET}"
[[ -n $git_colored ]] && line+=" ${git_colored}${RESET}"
[[ -n $worktree ]] && line+=" ${C_MUTED}wt:${worktree}${RESET}"
[[ -n $ctx_colored ]] && line+=" ${ctx_colored}${RESET}"
if [[ -n $model ]]; then
  line+=" ${C_MUTED}${model}"
  [[ -n $effort ]] && line+=" ${effort}"
  line+="${RESET}"
fi

extra_n=${#extra_dirs[@]}
if (( extra_n )); then
  extra_avail=$(( cols - 4 ))
  extra_total=$(( 2 * (extra_n - 1) ))
  for (( i=0; i<extra_n; i++ )); do
    collapse_home "${extra_dirs[i]}"
    extra_dirs[i]=$REPLY
    extra_total=$(( extra_total + ${#extra_dirs[i]} ))
  done

  extra_shown=$extra_n extra_more="" extra_share=$extra_avail
  if (( extra_total > extra_avail )); then
    # Each shown path gets an equal share of the row; fewer paths are shown,
    # followed by a "+N more" count, until the share reaches 12 columns.
    while :; do
      extra_more="" reserve=0
      if (( extra_shown < extra_n )); then
        extra_more="+$(( extra_n - extra_shown )) more"
        reserve=$(( 2 + ${#extra_more} ))
      fi
      extra_share=$(( (extra_avail - 2 * (extra_shown - 1) - reserve) / extra_shown ))
      (( extra_share >= 12 || extra_shown == 1 )) && break
      extra_shown=$(( extra_shown - 1 ))
    done
    (( extra_share < 12 )) && extra_share=12
  fi

  line+=$'\n'"${C_MUTED}+ ${RESET}"
  for (( i=0; i<extra_shown; i++ )); do
    (( i )) && line+="  "
    line+="${C_DIR}$(shrink_path "${extra_dirs[i]}" "$extra_share")${RESET}"
  done
  [[ -n $extra_more ]] && line+="  ${C_MUTED}${extra_more}${RESET}"
fi
printf '%s' "$line"
