---
name: extract-public-repo
description: Use when publishing an internal or private repository as a public one — spinning off an open-source project, a public SDK/client, or any subset of a private codebase intended for an external audience.
argument-hint: "[source-repo-path]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git status*)
  - Bash(git log*)
  - Bash(git show*)
  - Bash(git diff*)
  - Bash(git branch*)
  - Bash(git config*)
  - Bash(git init*)
  - Bash(git add*)
  - Bash(git commit*)
  - Bash(git rm*)
  - Bash(git clone*)
  - Bash(uvx --from git-filter-repo git-filter-repo*)
  - Bash(gitleaks*)
  - Bash(trufflehog*)
  - Bash(mv*)
  - Bash(jq*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/resolve-source.sh*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/init-extraction.sh*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/scan-secrets.sh*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/fresh-history.sh*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/migrate-claude-metadata.sh*)
---

# Extract Public Repo

## Overview

Publishing to public is one-way and hard to reverse: once a commit is pushed to a public remote, anything in it — including old history — is exposed, even if later deleted. Treat every extraction as a security review first, a content-polish pass second.

If the reference repository is already public, inform the user and exit.

This skill prepares a repo locally — it does not push, add a remote, or create the actual public repo (`allowed-tools` above deliberately has no `git push`/`git remote`/`gh` patterns). Publishing is a separate, explicit action the user takes once they've reviewed the summary in step 9.

Every step below operates on a **copy** of the private repo, never the original in place — steps like the history reset are destructive, and running them on the source repo would destroy the user's actual private history.

Scripts referenced below live under `${CLAUDE_SKILL_DIR}/scripts/` — use that macro (it resolves to this skill's own directory) when invoking them; the working directory during extraction will be the target repo, not this skill's directory, so a bare relative path won't resolve.

## Process

Work in this order — get onto a safe copy first, then secrets, then polish.

1. **Resolve the source repo, then determine the destination.** Run `${CLAUDE_SKILL_DIR}/scripts/resolve-source.sh $1` — the script defaults to the current directory when no argument was given, normalizes to the repo's toplevel either way so an argument (or cwd) that points into a subdirectory still resolves correctly, and fails clearly if the path isn't inside a git repo at all — surface that error to the user and ask for the right path rather than guessing. State the resolved source repo path back to the user at the same time you ask where the new repo should live locally and what it should be named, so they can catch a wrong interpretation before anything is cloned — don't assume the destination name matches the private repo's directory name; public names are often chosen deliberately and may differ from an internal codename.
   - If the user wants the public repo to take over the private repo's *current* name, that means renaming the private repo's directory first. Ask explicitly before doing this — don't do it silently. Renaming the directory orphans Claude Code's own project state for it (session transcripts/memory under `~/.claude/projects/`, plus the entry in `~/.claude.json`) unless that state is migrated too — there's no official `claude project` command for this (it only offers `purge`, which deletes), but run `${CLAUDE_SKILL_DIR}/scripts/migrate-claude-metadata.sh <old-abs-path> <new-abs-path>` after the `mv` to do it: it relocates the `~/.claude/projects/` directory and moves the matching key in `~/.claude.json`, backing the latter up first and validating before swapping it in. **Caveat:** if the currently-running session was itself launched from the old path, it stays pinned to the old project path in memory until it ends — that one session's own transcript keeps writing to the old location regardless; only a fresh session started from the new path picks up the migrated history.
2. **Create an independent copy at that destination.** Run `${CLAUDE_SKILL_DIR}/scripts/init-extraction.sh <source-repo> <dest-dir>` — it clones the private repo into the new location and refuses to run if the destination already exists or is nested inside/around the source. Every step from here on targets `<dest-dir>`; the original private repo is never touched.
3. **Scan for secrets, credentials, and PII — in history, not just the working tree.** Run `${CLAUDE_SKILL_DIR}/scripts/scan-secrets.sh <dest-dir>` — it runs gitleaks/trufflehog if installed, plus a pattern-based fallback (key-shaped strings, internal hostnames, Slack/Jira/Linear links) across full git history and the working tree, and checks for a LICENSE file. It exits non-zero on any finding. This is a mechanical check — run it, don't try to eyeball history manually. A finding here means a real secret was likely exposed: flag it to the user for credential rotation (see Common Mistakes) regardless of what happens to history next.
4. **Decide the git history strategy.** Default to **fresh history** — run `${CLAUDE_SKILL_DIR}/scripts/fresh-history.sh <dest-dir>` once the working tree itself is clean (it squashes to a single initial commit, preserving `user.name`/`user.email`). Only keep filtered history (via `uvx --from git-filter-repo git-filter-repo`, not `filter-branch`) if preserving commit history has clear value *and* every commit passes `scan-secrets.sh` clean. Running it through `uvx` avoids requiring a persistent install; it works identically to the `git filter-repo` subcommand form since it's the same script. Re-run `scan-secrets.sh` after either path to confirm nothing survived.
5. **Strip development working notes** — code comments or docs narrating the sequence of decisions, internal debates, or "why we changed this" commentary that only made sense during private iteration.
6. **Professionalize remaining content** — consistent style, remove TODO/FIXME items that reference internal context, align with community-standard best practices.
7. **Give special attention to README.md** and other first-touch docs (CONTRIBUTING, CLAUDE.md, other agent/dev instructions) — these are the first thing a visitor sees and are the most likely place internal context leaks.
8. **Check licensing** — `scan-secrets.sh` already flags a missing LICENSE file; choosing which license and adding it is a policy decision for the owner, not something to presume. Also check that no bundled dependency's license conflicts with going public.
9. **Flag anything requiring discussion** before proceeding — a found secret, a change big enough to alter behavior, a dependency that can't ship publicly.
10. **Summarize for review** — present what will be included (or excluded, if shorter) so the user can review quickly before the repo goes live.

## Common Mistakes

| Mistake | Why it matters |
|---|---|
| Running history-rewriting steps on the original private repo | `fresh-history.sh` / `git-filter-repo` are destructive — always clone to a destination first with `init-extraction.sh` and operate there |
| Renaming the private repo's directory without running `migrate-claude-metadata.sh` after | Orphans that project's Claude Code session transcripts/memory and its `~/.claude.json` entry under the old path |
| Assuming the currently-running session relocates immediately after migration | It stays pinned to the old project path in memory until it ends — only a fresh session from the new path picks up the migrated history |
| Assuming the public repo's name matches the private repo's directory name | Public names are a deliberate choice (no internal codenames) — ask, don't infer |
| Scanning only current files for secrets | Secrets committed and later deleted are still in git history and will be exposed the moment history is pushed public |
| Treating history-scrubbing as sufficient once a real secret is found | If the secret was ever pushed anywhere it's already exposed — rotate the credential, don't just remove it from history |
| Using `git filter-branch` | Deprecated and error-prone; use `uvx --from git-filter-repo git-filter-repo` if history must be preserved |
| Polishing only README.md | Working notes and internal context hide in code comments, other docs, and config just as often |
| Skipping the "already public" check | Re-running extraction on an already-public repo wastes work and risks clobbering community contributions |
