#!/usr/bin/env bash
# Fast, non-Nix setup for a Linux box reached over SSH (e.g. an AWS EC2 instance).
# Unlike bootstrap.sh (nix-darwin, full reproducibility), this favors speed:
# no Nix, no reboot-safe declarative state, just get zsh/neovim/herdr working
# the way they do on the Mac. Re-run any time; every step is idempotent.
#
# Tools are fetched as static release binaries wherever the upstream project
# publishes one, so this works the same on Debian/Ubuntu, Amazon Linux/Fedora,
# Arch, Alpine, etc. instead of depending on any one distro's package repo.
# Only git, zsh, and a few build deps (needs /etc/shells registration, apt
# repos, etc.) go through the system package manager, whichever of
# apt/dnf/yum/pacman/zypper/apk is present.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share"
mkdir -p "$BIN" "$SHARE"

case "$(uname -m)" in
  x86_64) ARCH_GNU=x86_64; ARCH_ALT=amd64; ARCH_NVIM=x86_64; ARCH_TS=x64 ;;
  aarch64 | arm64) ARCH_GNU=aarch64; ARCH_ALT=arm64; ARCH_NVIM=arm64; ARCH_TS=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# Resolves to the version tag of a GitHub repo's latest release (e.g. "v10.4.2")
# without hitting the rate-limited API: the /releases/latest redirect lands on
# a URL ending in /tag/<name>.
latest_tag() {
  curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed -E 's#.*/tag/##'
}

echo "==> Step 1: git via the system package manager"
# Everything past this point may need to clone something (zsh plugins,
# omp's installer isn't git-based but Claude Code/other tooling assumes git
# exists), so it goes first and on its own.
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update -y && $SUDO apt-get install -y git
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y git
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y git
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --noconfirm git
elif command -v zypper >/dev/null 2>&1; then
  $SUDO zypper install -y git
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add git
else
  echo "    No known package manager found; install git yourself, then re-run this script." >&2
  exit 1
fi

echo "==> Step 2: zsh, curl, unzip, a C compiler, python3-venv via the system package manager"
# unzip is required by the fnm installer in Step 6. A C compiler is required
# by nvim-treesitter to compile parsers (Step 3b/Step 4's `:TSUpdate` /
# `.install()`). python3-venv is required by mason to install basedpyright
# (a pypi package mason installs into its own venv).
# Always run the install (package managers no-op on already-installed
# packages) so a re-run after adding a new base package here still picks it up.
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get install -y zsh curl unzip gcc python3-venv
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y zsh curl unzip gcc python3
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y zsh curl unzip gcc python3
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --noconfirm zsh curl unzip gcc python
elif command -v zypper >/dev/null 2>&1; then
  $SUDO zypper install -y zsh curl unzip gcc python3 python3-venv
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add zsh curl unzip gcc musl-dev python3 py3-venv
else
  echo "    No known package manager found; install zsh/curl/unzip/gcc/python3 yourself, then re-run this script." >&2
  exit 1
fi

echo "==> Step 3: neovim (release tarball, distro repos are usually too old for this config)"
NVIM_DIR="$SHARE/nvim-linux-$ARCH_NVIM"
if [ -x "$NVIM_DIR/bin/nvim" ]; then
  echo "    already installed, skipping"
else
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$ARCH_NVIM.tar.gz" \
    | tar -xz -C "$SHARE"
fi
ln -sf "$NVIM_DIR/bin/nvim" "$BIN/nvim"

echo "==> Step 3b: tree-sitter CLI (needed by nvim-treesitter to compile parsers)"
if [ -x "$BIN/tree-sitter" ]; then
  echo "    already installed, skipping"
else
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$ARCH_TS.gz" \
    | gunzip > "$BIN/tree-sitter"
  chmod +x "$BIN/tree-sitter"
fi

echo "==> Step 4: ripgrep, fd, fzf, jq (static binaries, no distro package needed)"
if [ -x "$BIN/rg" ]; then
  echo "    ripgrep already installed, skipping"
else
  RG_TAG="$(latest_tag BurntSushi/ripgrep)"
  curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RG_TAG}/ripgrep-${RG_TAG}-${ARCH_GNU}-unknown-linux-musl.tar.gz" \
    | tar -xz -C /tmp
  install -m755 "/tmp/ripgrep-${RG_TAG}-${ARCH_GNU}-unknown-linux-musl/rg" "$BIN/rg"
  rm -rf "/tmp/ripgrep-${RG_TAG}-${ARCH_GNU}-unknown-linux-musl"
fi

if [ -x "$BIN/fd" ]; then
  echo "    fd already installed, skipping"
else
  FD_TAG="$(latest_tag sharkdp/fd)"
  curl -fsSL "https://github.com/sharkdp/fd/releases/download/${FD_TAG}/fd-${FD_TAG}-${ARCH_GNU}-unknown-linux-musl.tar.gz" \
    | tar -xz -C /tmp
  install -m755 "/tmp/fd-${FD_TAG}-${ARCH_GNU}-unknown-linux-musl/fd" "$BIN/fd"
  rm -rf "/tmp/fd-${FD_TAG}-${ARCH_GNU}-unknown-linux-musl"
fi

if [ -x "$BIN/fzf" ]; then
  echo "    fzf already installed, skipping"
else
  FZF_TAG="$(latest_tag junegunn/fzf)"
  FZF_VER="${FZF_TAG#v}"
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/${FZF_TAG}/fzf-${FZF_VER}-linux_${ARCH_ALT}.tar.gz" \
    | tar -xz -C "$BIN" fzf
fi

if [ -x "$BIN/jq" ]; then
  echo "    jq already installed, skipping"
else
  curl -fsSL -o "$BIN/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${ARCH_ALT}"
  chmod +x "$BIN/jq"
fi

echo "==> Step 5: zsh-autosuggestions and zsh-syntax-highlighting"
ZSH_PLUGINS="$HOME/.zsh/plugins"
mkdir -p "$ZSH_PLUGINS"
[ -d "$ZSH_PLUGINS/zsh-autosuggestions" ] || git clone -q --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS/zsh-autosuggestions"
[ -d "$ZSH_PLUGINS/zsh-syntax-highlighting" ] || git clone -q --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS/zsh-syntax-highlighting"

echo "==> Step 6: Node.js via fnm (needed by mason for npm-based LSP servers)"
FNM_DIR="$SHARE/fnm"
if [ -x "$FNM_DIR/fnm" ]; then
  echo "    fnm already installed, skipping"
else
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
fi
ln -sf "$FNM_DIR/fnm" "$BIN/fnm"
export PATH="$BIN:$PATH"
eval "$(fnm env)"
fnm install --lts

echo "==> Step 7: starship prompt"
if command -v starship >/dev/null 2>&1 || [ -x "$BIN/starship" ]; then
  echo "    starship already installed, skipping"
else
  curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$BIN"
fi

echo "==> Step 8: herdr (so 'herdr --remote' from your Mac has a server to attach to)"
if command -v herdr >/dev/null 2>&1 || [ -x "$BIN/herdr" ]; then
  echo "    herdr already installed, skipping"
else
  curl -fsSL https://herdr.dev/install.sh | sh
fi

echo "==> Step 9: Claude Code"
if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
  echo "    already installed, skipping"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "==> Step 10: omp (can1357/oh-my-pi - coding agent with the IDE wired in)"
if [ -x "$BIN/omp" ]; then
  echo "    already installed, skipping"
else
  OMP_TAG="$(latest_tag can1357/oh-my-pi)"
  curl -fsSL -o "$BIN/omp" "https://github.com/can1357/oh-my-pi/releases/download/${OMP_TAG}/omp-linux-${ARCH_TS}"
  chmod +x "$BIN/omp"
fi

echo "==> Step 11: symlink configs from this repo"
# ln -sfn nests the link *inside* an existing real dir/file instead of
# replacing it, so move anything real out of the way first.
link() {
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    mv "$2" "$2.bak.$(date +%s)"
  fi
  ln -sfn "$1" "$2"
}
mkdir -p "$HOME/.config" "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.omp/agent"
link "$DIR/home/.config/nvim" "$HOME/.config/nvim"
link "$DIR/home/.config/herdr" "$HOME/.config/herdr"
link "$DIR/home/.claude/settings.json" "$HOME/.claude/settings.json"
link "$DIR/home/.omp/agent/config.yml" "$HOME/.omp/agent/config.yml"
link "$DIR/home/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link "$DIR/home/AGENTS.md" "$HOME/.codex/AGENTS.md"
link "$DIR/home/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
link "$DIR/home/AGENTS.md" "$HOME/.omp/agent/AGENTS.md"
# wezterm is a local terminal emulator; nothing to symlink for a headless box.

echo "==> Step 12: ~/.zshrc and ~/.config/starship.toml"
# Plain-text mirror of the programs.zsh / programs.starship settings in
# home.nix. Keep the two in sync by hand if those change.
cat > "$HOME/.zshrc" <<'EOF'
export EDITOR=nvim
export PATH="$HOME/.local/bin:$PATH"

autoload -Uz compinit && compinit
eval "$(fnm env --use-on-cd)"
eval "$(starship init zsh)"

source "$HOME/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
bindkey '^f' autosuggest-accept

alias ..="cd .."
alias add="git add ."
alias push="git push"
alias pull="git pull"
alias m="git switch main"
alias cc="claude --dangerously-skip-permissions"
alias co="codex --full-auto"

# Must be sourced last.
source "$HOME/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
EOF

cat > "$HOME/.config/starship.toml" <<'EOF'
add_newline = false
format = "$directory$git_branch$git_status$cmd_duration$line_break$character"

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"

[cmd_duration]
format = "[$duration]($style) "
EOF

if [ "$(getent passwd "$(whoami)" | cut -d: -f7 2>/dev/null)" != "$(command -v zsh)" ]; then
  echo "==> Step 13: set zsh as the login shell"
  # Plain chsh prompts for the *user's* password, which hangs over a non-tty
  # SSH session; going through sudo changes it without that prompt.
  $SUDO chsh -s "$(command -v zsh)" "$(whoami)" || echo "    chsh failed, run it yourself: chsh -s $(command -v zsh)"
fi

echo "==> Done. Start a new shell (or re-ssh) to pick up zsh, then run 'herdr server' here."
echo "    From your Mac: herdr --remote <user>@<this-host>"
