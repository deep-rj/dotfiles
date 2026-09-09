# dotfiles

Personal shell and tool configuration, kept here so it can be bootstrapped onto
any new machine (laptop or ephemeral cloud GPU pod) in one command instead of
being reconfigured by hand each time.

## Bootstrap

```bash
git clone git@github.com:deep-rj/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

Safe to re-run — `install.sh` is idempotent. It installs Oh My Zsh and its
third-party plugins/theme if missing, symlinks the tracked config files into
`$HOME`, and merges the Claude Code status line into `~/.claude/settings.json`
without clobbering other settings already there.

## What's tracked

| Path in repo | Symlinked to | Purpose |
|---|---|---|
| `zsh/.zshrc` | `~/.zshrc` | Oh My Zsh config: theme, plugins |
| `zsh/.p10k.zsh` | `~/.p10k.zsh` | Powerlevel10k prompt config |
| `bash/.bashrc` | `~/.bashrc` | Bash fallback for shells/images without zsh |
| `git/.gitconfig` | `~/.gitconfig` | Git identity |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Claude Code status line script |
| `claude/settings.snippet.json` | merged into `~/.claude/settings.json` | Registers the status line command |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global Claude Code instructions (all projects) |

Third-party frameworks (Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting,
Powerlevel10k) are **not** vendored here — `install.sh` clones them fresh from
their own repos on each machine.

## Not tracked, on purpose

SSH keys and any other secrets never go in this repo. Since this repo is
public, that also rules out anything else sensitive — regenerate/provision
secrets per machine instead.
