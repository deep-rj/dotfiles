#!/usr/bin/env bash
# Migrates Claude Code's own project state - session transcripts/memory under
# ~/.claude/projects/, plus the per-project entry in ~/.claude.json (trust
# status, MCP config, session history stats) - from an old absolute repo path
# to a new one after a directory rename.
#
# This is an empirically-verified manual procedure (successfully run twice on
# real project renames), not an officially documented Claude Code command.
# Project directory names are assumed to be the path with "/" replaced by
# "-"; if that doesn't match an existing directory, this script aborts rather
# than guessing further.
#
# Usage: migrate-claude-metadata.sh <old-abs-path> <new-abs-path>
set -euo pipefail

OLD="${1:?usage: migrate-claude-metadata.sh <old-abs-path> <new-abs-path>}"
NEW="${2:?usage: migrate-claude-metadata.sh <old-abs-path> <new-abs-path>}"

slug() { printf '%s' "$1" | sed 's#/#-#g'; }

PROJECTS_DIR="$HOME/.claude/projects"
OLD_DIR="$PROJECTS_DIR/$(slug "$OLD")"
NEW_DIR="$PROJECTS_DIR/$(slug "$NEW")"

if [ ! -d "$OLD_DIR" ]; then
  echo "error: no Claude project dir found at $OLD_DIR for $OLD - aborting, nothing to migrate" >&2
  exit 2
fi
if [ -e "$NEW_DIR" ]; then
  echo "error: $NEW_DIR already exists - refusing to merge blindly, resolve manually" >&2
  exit 2
fi

echo "== Moving session/memory data =="
mkdir "$NEW_DIR"
shopt -s dotglob nullglob
mv "$OLD_DIR"/* "$NEW_DIR"/
shopt -u dotglob nullglob
rmdir "$OLD_DIR" && echo "old project dir removed: $OLD_DIR"
echo "new project dir now has $(ls "$NEW_DIR" | wc -l) entries"

echo
echo "== Migrating ~/.claude.json project entry =="
CLAUDE_JSON="$HOME/.claude.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required for this step but not installed" >&2
  exit 2
fi

if ! jq -e --arg old "$OLD" '.projects | has($old)' "$CLAUDE_JSON" >/dev/null; then
  echo "note: no ~/.claude.json entry for $OLD - skipping that part"
else
  BACKUP="${TMPDIR:-/tmp}/claude.json.bak.$(date +%s)"
  cp -p "$CLAUDE_JSON" "$BACKUP"
  echo "backed up ~/.claude.json to $BACKUP"

  TMP_JSON=$(mktemp)
  jq --arg old "$OLD" --arg new "$NEW" \
    '.projects[$new] = .projects[$old] | .projects |= del(.[$old])' \
    "$CLAUDE_JSON" > "$TMP_JSON"

  jq -e '.' "$TMP_JSON" >/dev/null || { echo "error: produced invalid JSON, aborting - original untouched" >&2; exit 2; }
  jq -e --arg new "$NEW" --arg old "$OLD" \
    '.projects | has($new) and (has($old) | not)' "$TMP_JSON" >/dev/null \
    || { echo "error: migrated JSON failed sanity check, aborting - original untouched" >&2; exit 2; }

  mv "$TMP_JSON" "$CLAUDE_JSON"
  chmod 600 "$CLAUDE_JSON"
  echo "~/.claude.json project entry migrated ($OLD -> $NEW)"
fi

echo
echo "== Done =="
echo "IMPORTANT: if the CURRENTLY RUNNING session was launched from $OLD,"
echo "it stays pinned to the old project path in memory until it ends -"
echo "this script cannot change that live setting. Start a fresh session"
echo "from $NEW to pick up the migrated history by default."
