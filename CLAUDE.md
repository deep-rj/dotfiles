# Dotfiles repo guidelines

Public repo that bootstraps shell, git and Claude Code configuration onto any
machine (laptop or ephemeral cloud pod) with one command. Note that
`claude/CLAUDE.md` is the global instruction file symlinked to
`~/.claude/CLAUDE.md`; this file only governs work inside this repo.

## Principles

- **Portability first.** Do not hardcode usernames, home directories, mount
  points (e.g. `/workspace`), hostnames or provider-specific paths in tracked
  files. Machine-specific settings belong in a tracked profile under
  `profiles/`, never in untracked local files. Push back on changes that break portability, or propose an
  approach that keeps the core portable.
- **Lightweight and fast.** Keep shell startup quick and dependencies few. Prefer
  built-ins over extra tools, avoid work at every shell start that could be done
  once at install time, and make optional dependencies degrade gracefully.
- **Safe by default.** Avoid destructive or irreversible operations. Where one
  is unavoidable, back up first (see `install.sh`), preview before applying, and
  keep installs idempotent. Never track secrets or credentials.
- **Stay current.** If a tool or library here has been superseded by something
  the community has clearly moved to, flag it and propose the update.
- **Tools must not pollute the repo.** Files in `$HOME` are symlinks into this
  repo, so installers that append to them (e.g. `conda init`) modify tracked
  files. Review `git diff` for machine-specific additions before committing.

## Documentation

- Keep `README.md` in sync with every change to what is installed, what is
  required versus optional, and what is replaced or backed up.
- Be concise; this is a public repo. Code, comments and docs must read as
  professional, timeless statements about the current state.
- Do not record how a decision was reached, conversation history or other
  redundant detail in code, comments or docs.
