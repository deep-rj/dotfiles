#!/usr/bin/env bash
# Creates an independent local copy of a repo to extract from, so every later
# step (secret scan, history reset, editing) operates on the COPY - the
# original private repo is never touched or put at risk.
#
# Usage: init-extraction.sh <source-repo> <dest-dir>
set -euo pipefail

SRC="${1:?usage: init-extraction.sh <source-repo> <dest-dir>}"
DEST="${2:?usage: init-extraction.sh <source-repo> <dest-dir>}"

if [ ! -d "$SRC/.git" ]; then
  echo "error: $SRC is not a git repository" >&2
  exit 2
fi
SRC_ABS=$(cd "$SRC" && pwd)

if [ -e "$DEST" ]; then
  echo "error: $DEST already exists - refusing to overwrite" >&2
  exit 2
fi
DEST_PARENT=$(cd "$(dirname "$DEST")" && pwd)
DEST_ABS="$DEST_PARENT/$(basename "$DEST")"

case "$DEST_ABS/" in
  "$SRC_ABS/"*) echo "error: destination cannot be inside the source repo" >&2; exit 2 ;;
esac
case "$SRC_ABS/" in
  "$DEST_ABS/"*) echo "error: source cannot be inside the destination" >&2; exit 2 ;;
esac

git clone -- "$SRC_ABS" "$DEST_ABS"
echo
echo "Cloned $SRC_ABS -> $DEST_ABS"
echo "All further extraction steps (scanning, history reset, editing) should target $DEST_ABS."
echo "$SRC_ABS is untouched - leave it that way."
