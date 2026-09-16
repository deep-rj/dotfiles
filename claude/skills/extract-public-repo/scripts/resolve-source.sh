#!/usr/bin/env bash
# Resolves the private repo to extract from, so the skill can state back to
# the user exactly which repo it interpreted before anything is cloned.
#
# Usage: resolve-source.sh [path]
# Defaults to the current directory when no path is given. Normalizes to the
# repo's toplevel regardless of whether the given path (or cwd) is a
# subdirectory, so a mistyped or nested path is caught here instead of
# surfacing a more confusing "not a git repository" error later in
# init-extraction.sh (which requires an exact repo root).
set -euo pipefail

SRC="${1:-.}"

if [ ! -d "$SRC" ]; then
  echo "error: $SRC is not a directory" >&2
  exit 2
fi

if ! TOPLEVEL=$(cd "$SRC" && git rev-parse --show-toplevel 2>/dev/null); then
  echo "error: $SRC is not inside a git repository" >&2
  exit 2
fi

echo "$TOPLEVEL"
