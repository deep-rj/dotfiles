#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|MultiEdit|NotebookEdit): auto-format the
# touched file with ruff (Python) or biome (JS/TS), then tell Claude about
# it -- but only when there's something worth saying.
#
# Silent on a clean pass (nothing changed, nothing unfixable): injecting
# "formatted cleanly" on every edit would just permanently bloat every
# future --resume/--continue transcript for no benefit.
#
# Two cases are worth surfacing, and they use different channels:
#   - Unfixable lint errors remain -> decision:block + reason. This is
#     corrective: it should push Claude to actually address it, not just
#     mention it in passing (community consensus on PostToolUse hooks;
#     see e.g. disler/claude-code-hooks-mastery).
#   - The formatter silently rewrote the file -> additionalContext. This
#     is informational only (Claude's in-memory copy of the file is now
#     stale), nothing to fix, so it doesn't need the "block" treatment.
set -uo pipefail

f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

# Trims noisy tool output to a size sane for a context message.
truncate_out() {
  head -c 3000
}

decision=""
context=""

case "$f" in
  *.py|*.pyi|*.ipynb)
    command -v uvx >/dev/null 2>&1 || exit 0
    before=$(cat "$f" 2>/dev/null)
    check_out=$(uvx ruff check --fix "$f" 2>&1)
    check_status=$?
    uvx ruff format "$f" >/dev/null 2>&1
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
    before=$(cat "$f" 2>/dev/null)
    biome_out=$(npx --no-install @biomejs/biome check --write "$f" 2>&1)
    biome_status=$?
    after=$(cat "$f" 2>/dev/null)

    # npx/npm plumbing failures (package not cached, no network, etc.)
    # aren't lint findings -- stay silent rather than confusing Claude
    # with tooling noise it can't do anything about.
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
