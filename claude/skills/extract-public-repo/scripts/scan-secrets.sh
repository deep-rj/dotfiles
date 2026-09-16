#!/usr/bin/env bash
# Deterministic pre-publish scan: secrets/credentials across full git history
# AND the working tree, plus common internal-reference patterns (internal
# hostnames, ticket/Slack links, key-shaped strings). Exit 0 = clean,
# 1 = findings (or missing LICENSE), 2 = usage error.
#
# Usage: scan-secrets.sh <repo-path>
set -euo pipefail

REPO="${1:-.}"
cd "$REPO"

if [ ! -d .git ]; then
  echo "error: $REPO is not a git repository" >&2
  exit 2
fi

FOUND=0

echo "== Secret scanners =="
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --log-opts="--all" --no-banner || FOUND=1
else
  echo "WARNING: gitleaks not installed - SKIPPING this scan pass (falling back to weaker pattern matching only)." >&2
  echo "  Install it for real secret-scanning coverage: sudo apt-get install -y gitleaks" >&2
  echo "  (or see other install options: https://github.com/gitleaks/gitleaks#installing)" >&2
fi

if command -v trufflehog >/dev/null 2>&1; then
  trufflehog git "file://$(pwd)" --only-verified --fail || FOUND=1
else
  echo "WARNING: trufflehog not installed - SKIPPING this scan pass (loses verified-live-credential detection)." >&2
  echo "  Install it: curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b ~/.local/bin" >&2
fi

echo
echo "== Fallback pattern scan (full history + working tree) =="
PATTERNS='(sk-live-[A-Za-z0-9]+|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|postgres(ql)?://[^ ]*:[^ ]*@|mongodb(\+srv)?://[^ ]*:[^ ]*@|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(corp|internal)\.[A-Za-z]{2,}|https?://[a-z0-9.-]*\.slack\.com/archives/|https?://[a-z0-9.-]*\.atlassian\.net/browse/|https?://linear\.app/)'

HIST_HITS=$(git log -p --all 2>/dev/null | grep -EnoI "$PATTERNS" || true)
if [ -n "$HIST_HITS" ]; then
  echo "git history hits:"
  echo "$HIST_HITS"
  FOUND=1
fi

TREE_HITS=$(grep -rEnoI "$PATTERNS" --exclude-dir=.git . || true)
if [ -n "$TREE_HITS" ]; then
  echo "working-tree hits:"
  echo "$TREE_HITS"
  FOUND=1
fi

if [ -z "$HIST_HITS" ] && [ -z "$TREE_HITS" ]; then
  echo "no fallback-pattern hits"
fi

echo
echo "== License check =="
if compgen -G "LICENSE*" >/dev/null || compgen -G "LICENCE*" >/dev/null; then
  echo "LICENSE file present"
else
  echo "no LICENSE file found"
  FOUND=1
fi

exit $FOUND
