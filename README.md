# dotfiles

Personal shell and tool configuration, kept here so it can be bootstrapped onto
any new machine (laptop or ephemeral cloud GPU pod) in one command instead of
being reconfigured by hand each time.

## Prerequisites

`install.sh` checks for the hard requirements below and fails with a clear
message if one's missing. The rest are only needed for the specific piece
they power — without them that piece silently does nothing rather than
breaking the bootstrap.

| Tool | Needed for | Hard requirement? | Get it |
|---|---|---|---|
| `git` | cloning this repo, and Oh My Zsh + plugins | yes | preinstalled almost everywhere; else `apt install git` / `brew install git` |
| `bash` | running `install.sh` | yes | preinstalled almost everywhere |
| `python3` | the settings.json merge (`claude/merge_settings.py`) | yes | Linux: `apt install python3`; macOS: `xcode-select --install` or `brew install python3` |
| `zsh` | actually using `.zshrc` (Oh My Zsh, Powerlevel10k) | no — `.bashrc` is tracked as a fallback | `apt install zsh` / `brew install zsh` |
| `jq` | Claude Code's PostToolUse hook (reading tool-call JSON) and the `extract-public-repo` skill's `migrate-claude-metadata.sh` | no — hook no-ops without it; the skill script hard-errors if it's missing | `apt install jq` / `brew install jq` |
| `uv` (for `uvx`) | the hook's Python auto-fix/format (ruff), and running `git-filter-repo` on demand (via `uvx --from git-filter-repo git-filter-repo`) in the `extract-public-repo` skill | no | https://docs.astral.sh/uv/getting-started/installation/ |
| `nvm` + Node (for `npx`) | the hook's JS/TS auto-fix/format (biome) | no | https://github.com/nvm-sh/nvm#install--update-script |
| `gitleaks` | the `extract-public-repo` skill's secret scan | no — scan falls back to weaker pattern matching without it | `apt install gitleaks` / see https://github.com/gitleaks/gitleaks#installing |
| `trufflehog` | the `extract-public-repo` skill's secret scan (verified-live-credential detection) | no — scan skips this pass without it | https://github.com/trufflesecurity/trufflehog#installation |
| [Claude Code](https://claude.com/product/claude-code) | `statusLine`/hooks/`CLAUDE.md`/skills to have any effect | no — shell/git config works standalone | see their install docs |

## Bootstrap

```bash
git clone git@github.com:deep-rj/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

Safe to re-run — `install.sh` is idempotent. It installs Oh My Zsh and its
third-party plugins/theme if missing, symlinks the tracked config files into
`$HOME`, and deep-merges `claude/settings.snippet.json` into
`~/.claude/settings.json` key by key. Every run starts by printing a plan
(new symlinks, diffs for files that already exist with different content,
and settings.json additions/conflicts) before touching anything. If a key
that settings.snippet.json wants already exists locally with a different value
(e.g. you hand-edited the `hooks` command), that key is left alone and
reported as a conflict instead of being silently overwritten — reconcile it
by hand or update `settings.snippet.json` to match.

If there's nothing to do, it says so and exits. Otherwise, when run from a
terminal it shows the plan and asks for confirmation; pass `--yes` to apply
without asking (e.g. unattended pod provisioning) or `--dry-run` to only
preview.

Any file a symlink would clobber is moved first, not deleted — each run
gets its own `~/.dotfiles-backup/<timestamp>/` directory, and clobbered
files land there under their original relative path (e.g.
`~/.dotfiles-backup/20260915154226/.bashrc`). Nothing prunes these
automatically; once you've confirmed you don't need an old version, it's
safe to delete its backup directory.

## What's tracked

| Path in repo | Symlinked to | Purpose |
|---|---|---|
| `zsh/.zshrc` | `~/.zshrc` | Oh My Zsh config: theme, plugins |
| `zsh/.p10k.zsh` | `~/.p10k.zsh` | Powerlevel10k prompt config |
| `bash/.bashrc` | `~/.bashrc` | Bash fallback for shells/images without zsh |
| `git/.gitconfig` | `~/.gitconfig` | Git identity |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Claude Code status line script |
| `claude/settings.snippet.json` | merged into `~/.claude/settings.json` | Registers the status line command, ruff (Python) and biome (JS/TS) auto-fix/format hooks, and attribution suppression |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global Claude Code instructions (all projects) |
| `claude/skills/extract-public-repo/` | `~/.claude/skills/extract-public-repo/` | Skill for spinning off a private repo (or subset of one) as a public repo, safely |

Third-party frameworks (Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting,
Powerlevel10k) are **not** vendored here — `install.sh` clones them fresh from
their own repos on each machine.

`claude/merge_settings.py` does the settings.json merge described above; it's
invoked by `install.sh`, not symlinked anywhere itself.

## Not tracked, on purpose

SSH keys and any other secrets never go in this repo. Since this repo is
public, that also rules out anything else sensitive — regenerate/provision
secrets per machine instead.
