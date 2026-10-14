# dotfiles

Bootstrap for my development environment on macOS and Linux (Arch, Debian/Ubuntu, Fedora).
The configs live in their own repos under [NBAFrigge](https://github.com/NBAFrigge):

| Repo | Links into $HOME |
| --- | --- |
| `zsh-config` | `.zshrc`, `.zshrc.local.example` |
| `tmux-config` | `.tmux.conf` |
| `nvim-config` | `.config/nvim` (whole repo) |
| `git-config` | `.gitconfig`, `.gitconfig.local.example`, `.config/git/ignore` |
| `kitty-config` | `.config/kitty/kitty.conf` |

Each tool repo has a `manifest` file (`source<TAB>target`, relative to $HOME) that the bootstrap reads.

## Install

```sh
curl -fsSL https://dots.frigge.dev/install | sh
```

What it does:

1. Installs packages (Homebrew on macOS; pacman, apt-get or dnf on Linux). Core packages are required; kitty and fonts are optional.
2. Clones each tool repo into `~/.config-repos/<name>` (or pulls it if already there).
3. Symlinks the files from each manifest. An existing file is moved to `~/.dotfiles-backup/<timestamp>/`, never deleted.
4. Copies `*.example` templates to their real names (`.zshrc.local`, `.gitconfig.local`) only if those do not exist.
5. Installs TPM into `~/.tmux/plugins/tpm` and switches the login shell to zsh if needed.

Options:

- `sh bootstrap.sh --update`: pull all repos, relink, skip package install.
- `DRY_RUN=1 sh bootstrap.sh`: print the actions without running them.
- `SKIP_PACKAGES=1 sh bootstrap.sh`: skip package installation.

Machine-specific settings go in `~/.zshrc.local` and `~/.gitconfig.local`; they are not in any repo.
