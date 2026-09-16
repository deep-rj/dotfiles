#!/usr/bin/env bash
# Replaces a repo's git history with a single fresh initial commit, preserving
# current working-tree contents and the existing user.name/user.email.
#
# Only run this after scan-secrets.sh passes clean on the WORKING TREE -
# this script removes old history, it does not vet current file contents.
#
# Usage: fresh-history.sh <repo-path> ["commit message"]
set -euo pipefail

REPO="${1:-.}"
MSG="${2:-Initial commit}"
cd "$REPO"

if [ ! -d .git ]; then
  echo "error: $REPO is not a git repository" >&2
  exit 2
fi

NAME=$(git config user.name || true)
EMAIL=$(git config user.email || true)

rm -rf .git
git init -q
[ -n "$NAME" ] && git config user.name "$NAME"
[ -n "$EMAIL" ] && git config user.email "$EMAIL"
git add -A
git commit -q -m "$MSG"

echo "History reset to a single commit on branch $(git branch --show-current)."
git log --oneline
