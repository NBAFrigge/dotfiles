#!/bin/sh
# dotfiles bootstrap: install packages, clone the tool repos, link configs into $HOME.
# Usage: curl -fsSL https://dots.frigge.dev/install | sh
#        sh bootstrap.sh [--update]
# Env:   DRY_RUN=1 print actions only    SKIP_PACKAGES=1 skip package install
set -eu

DOTFILES_GH_USER=NBAFrigge
TOOL_REPOS="zsh-config tmux-config nvim-config git-config kitty-config"
REPO_DIR="$HOME/.config-repos"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
TAB=$(printf '\t')
UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=1 ;;
        *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
run() {
    if [ "${DRY_RUN:-0}" = 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi
}

install_macos() {
    if ! command -v brew >/dev/null 2>&1; then
        info "installing Homebrew"
        if [ "${DRY_RUN:-0}" = 1 ]; then
            printf '[dry-run] NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL .../Homebrew/install/HEAD/install.sh)"\n'
        else
            NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
                || die "Homebrew install failed"
        fi
    else
        info "Homebrew already installed"
    fi
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
    done
    info "installing core packages (brew)"
    run brew install git zsh tmux neovim fzf ripgrep fd || die "core brew packages failed"
    info "installing extras (brew): kitty, JetBrains Mono Nerd Font"
    run brew install --cask kitty font-jetbrains-mono-nerd-font || warn "extras failed; install them manually"
}

install_linux() {
    if command -v pacman >/dev/null 2>&1; then
        PM=pacman; INSTALL="sudo pacman -S --needed --noconfirm"
        CORE="git zsh tmux neovim fzf ripgrep fd curl"
    elif command -v apt-get >/dev/null 2>&1; then
        PM=apt-get; INSTALL="sudo apt-get install -y"
        CORE="git zsh tmux neovim fzf ripgrep fd-find curl"
        run sudo apt-get update || warn "apt-get update failed"
    elif command -v dnf >/dev/null 2>&1; then
        PM=dnf; INSTALL="sudo dnf install -y"
        CORE="git zsh tmux neovim fzf ripgrep fd-find curl"
    else
        die "no supported package manager found (pacman, apt-get, dnf)"
    fi
    info "installing core packages ($PM): $CORE"
    # shellcheck disable=SC2086
    run $INSTALL $CORE || die "core package install failed"
    info "installing extras ($PM): kitty"
    # shellcheck disable=SC2086
    run $INSTALL kitty || warn "kitty not available via $PM; install it manually"
    if [ "$PM" = apt-get ]; then warn "Debian/Ubuntu name fd 'fdfind'; the fd alias in .zshrc will not apply"; fi
}

install_packages() {
    if [ "${SKIP_PACKAGES:-0}" = 1 ]; then info "SKIP_PACKAGES=1: skipping package install"; return 0; fi
    case "$(uname -s)" in
        Darwin) install_macos ;;
        Linux) install_linux ;;
        *) warn "unsupported OS $(uname -s): skipping package install" ;;
    esac
}

sync_repo() {
    name=$1; dir="$REPO_DIR/$name"
    url="https://github.com/$DOTFILES_GH_USER/$name.git"
    if [ -d "$dir/.git" ]; then
        info "pull $name"
        run git -C "$dir" pull --quiet --ff-only </dev/null || warn "pull failed for $name"
    else
        info "clone $name"
        run mkdir -p "$REPO_DIR"
        run git clone --quiet "$url" "$dir" </dev/null || warn "clone failed for $name"
    fi
}

link_file() {  # $1 absolute source, $2 path relative to $HOME (globals: POSIX sh has no local)
    lf_src=$1; lf_dst="$HOME/$2"
    if [ -L "$lf_dst" ]; then
        if [ "$(readlink "$lf_dst")" = "$lf_src" ]; then info "ok      ~/$2"; return 0; fi
        info "replace symlink ~/$2 (pointed elsewhere)"
        run rm "$lf_dst"
    elif [ -e "$lf_dst" ]; then
        info "backup  ~/$2 -> $BACKUP_DIR/$2"
        run mkdir -p "$(dirname "$BACKUP_DIR/$2")"
        run mv "$lf_dst" "$BACKUP_DIR/$2"
    fi
    run mkdir -p "$(dirname "$lf_dst")"
    run ln -s "$lf_src" "$lf_dst" || return 1
    info "link    ~/$2 -> $lf_src"
}

link_repo() {
    name=$1; dir="$REPO_DIR/$name"; manifest="$dir/manifest"
    if [ ! -f "$manifest" ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then info "[dry-run] $name is not cloned yet; mapping is read from its manifest after clone"; return 0; fi
        warn "$name has no manifest; skipping"; return 1
    fi
    while IFS="$TAB" read -r src dst || [ -n "$src" ]; do
        case "$src" in ''|'#'*) continue ;; esac
        [ -n "$dst" ] || continue
        case "$(basename "$src")" in manifest|README.md|.gitignore) continue ;; esac
        if [ "$src" = "." ]; then s="$dir"; else s="$dir/$src"; fi
        if [ ! -e "$s" ]; then warn "$name: $src missing in repo"; continue; fi
        link_file "$s" "$dst" || { warn "could not link ~/$dst"; continue; }
        case "$dst" in
            *.example)
                real="${dst%.example}"
                if [ -e "$HOME/$real" ] || [ -L "$HOME/$real" ]; then
                    info "keep    ~/$real (exists)"
                else
                    info "copy    template -> ~/$real (edit it)"
                    run cp "$s" "$HOME/$real" || warn "could not copy template to ~/$real"
                fi ;;
        esac
    done < "$manifest"
}

ensure_tpm() {
    tpm="$HOME/.tmux/plugins/tpm"
    if [ -d "$tpm" ]; then info "TPM present"; return 0; fi
    info "installing TPM into $tpm"
    run mkdir -p "$HOME/.tmux/plugins"
    run git clone --quiet --depth 1 https://github.com/tmux-plugins/tpm "$tpm" </dev/null || warn "TPM clone failed"
}

ensure_shell() {
    zsh_path=$(command -v zsh 2>/dev/null || true)
    if [ -z "$zsh_path" ]; then warn "zsh not installed; skipping shell change"; return 0; fi
    if [ "$(basename "${SHELL:-}")" = zsh ]; then info "login shell is already zsh"; return 0; fi
    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        warn "$zsh_path is not in /etc/shells; add it, then run: chsh -s $zsh_path"; return 0
    fi
    user_home=$(eval "echo ~$(id -un)")
    if [ "$HOME" != "$user_home" ]; then
        warn "HOME ($HOME) is not the login home ($user_home); not changing the shell"; return 0
    fi
    info "changing login shell to zsh"
    run chsh -s "$zsh_path" || warn "chsh failed; run manually: chsh -s $zsh_path"
}

info "dotfiles bootstrap (OS: $(uname -s), home: $HOME)"
if [ "$UPDATE" = 1 ]; then info "--update: skipping package install"; else install_packages; fi
for r in $TOOL_REPOS; do sync_repo "$r"; done
for r in $TOOL_REPOS; do link_repo "$r" || warn "linking $r failed"; done
ensure_tpm
ensure_shell
info "done. Backups (if any) are in $BACKUP_DIR"
