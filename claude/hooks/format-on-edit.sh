#!/usr/bin/env bash
# PostToolUse hook: auto-format edited files (ruff for Python, biome for JS/TS).
# Output back to Claude is conditional:
#   - unfixable lint errors remain -> decision:block with the tool output
#   - formatter rewrote the file   -> additionalContext (informational)
#   - otherwise                    -> silent
set -uo pipefail

f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

truncate_out() {
  head -n 40
}

decision=""
context=""

case "$f" in
  *.py|*.pyi|*.ipynb)
    command -v uvx >/dev/null 2>&1 || exit 0
    before=$(cat "$f" 2>/dev/null)
    check_out=$(uvx ruff check --fix --force-exclude "$f" 2>&1)
    check_status=$?
    uvx ruff format --force-exclude "$f" >/dev/null 2>&1
    after=$(cat "$f" 2>/dev/null)

    if [ "$check_status" != "0" ]; then
      decision="ruff could not auto-fix everything in $f:
$(printf '%s' "$check_out" | truncate_out)"
    elif [ "$before" != "$after" ]; then
      context="ruff auto-fixed/reformatted $f; re-read it if you need the current contents."
    fi
    ;;

  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    command -v npx >/dev/null 2>&1 || exit 0

    # Biome resolves config and its binary from cwd; anchor to the nearest biome config like ruff does.
    dir=$(dirname "$f")
    while [ "$dir" != "/" ] && [ ! -f "$dir/biome.json" ] && [ ! -f "$dir/biome.jsonc" ]; do
      dir=$(dirname "$dir")
    done
    if [ -f "$dir/biome.json" ] || [ -f "$dir/biome.jsonc" ]; then
      cd "$dir" || exit 0
    fi

    before=$(cat "$f" 2>/dev/null)
    biome_out=$(npx --no-install @biomejs/biome check --write --no-errors-on-unmatched "$f" 2>&1)
    biome_status=$?
    after=$(cat "$f" 2>/dev/null)

    # npx failing to resolve biome (not cached, offline) is not a lint finding.
    if printf '%s' "$biome_out" | grep -q '^npm error'; then
      exit 0
    fi

    if [ "$biome_status" != "0" ]; then
      decision="biome reported issues in $f:
$(printf '%s' "$biome_out" | truncate_out)"
    elif [ "$before" != "$after" ]; then
      context="biome auto-fixed/reformatted $f; re-read it if you need the current contents."
    fi
    ;;

  *)
    exit 0
    ;;
esac

if [ -n "$decision" ]; then
  jq -n --arg reason "$decision" '{decision: "block", reason: $reason}'
elif [ -n "$context" ]; then
  jq -n --arg ctx "$context" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
fi
exit 0
