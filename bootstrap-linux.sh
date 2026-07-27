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
# Claude Code/other tooling assumes git exists), so it goes first and on its own.
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

# Debian/Ubuntu's python3-venv only bundles ensurepip for the distro's default
# python3 (e.g. 3.10 on 22.04). If python3 resolves to a different version -
# e.g. installed via the deadsnakes PPA - `python3 -m venv` silently produces
# a venv with no working ensurepip, which breaks mason's basedpyright/ruff
# installs (both bootstrap their own venv via `python3 -m venv` + ensurepip).
if command -v apt-get >/dev/null 2>&1 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
  PY3_MINOR="$(python3 -c 'import sys; print(sys.version_info.minor)')"
  echo "    python3 (3.$PY3_MINOR) has no ensurepip; installing python3.$PY3_MINOR-venv"
  $SUDO apt-get install -y "python3.$PY3_MINOR-venv"
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
# v0.26+ binaries are built against glibc 2.39 and won't run on older hosts
# (e.g. Ubuntu 22.04's 2.35). Try latest first, since most hosts are fine, and
# fall back to the last release known to run on glibc 2.35 if it doesn't
# execute. Re-checks even when a binary is already there, so a previously
# broken install (or a later host glibc upgrade) self-heals on re-run.
TS_FALLBACK_TAG="v0.25.10"
install_tree_sitter() {
  curl -fsSL "$1" | gunzip > "$BIN/tree-sitter"
  chmod +x "$BIN/tree-sitter"
}
if [ -x "$BIN/tree-sitter" ] && "$BIN/tree-sitter" --version >/dev/null 2>&1; then
  echo "    already installed and working, skipping"
else
  install_tree_sitter "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$ARCH_TS.gz"
  if ! "$BIN/tree-sitter" --version >/dev/null 2>&1; then
    echo "    latest tree-sitter binary won't run on this host's glibc; falling back to $TS_FALLBACK_TAG"
    install_tree_sitter "https://github.com/tree-sitter/tree-sitter/releases/download/$TS_FALLBACK_TAG/tree-sitter-linux-$ARCH_TS.gz"
  fi
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

echo "==> Step 6b: uv (fast python project/venv manager, bicquant-style projects use it)"
if command -v uv >/dev/null 2>&1; then
  echo "    already installed, skipping"
  UV="$(command -v uv)"
elif [ -x "$BIN/uv" ]; then
  echo "    already installed, skipping"
  UV="$BIN/uv"
else
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" INSTALLER_NO_MODIFY_PATH=1 sh
  UV="$BIN/uv"
fi

echo "==> Step 6c: python packages for molten-nvim / jupytext.nvim"
# pynvim/jupyter-client are nvim's python3 remote-plugin host (molten is a remote
# plugin). Unlike the Nix build, this stock neovim release binary has no wrapper
# disabling provider auto-detection, so notebook.lua's g:python3_host_prog
# fallback (see there) just needs this venv's python3 to exist at a known path.
# ipykernel/jupytext are CLI tools jupytext.nvim/notebook.lua shell out to.
NVIM_PY="$SHARE/nvim-python"
if [ -x "$NVIM_PY/bin/python3" ]; then
  echo "    already installed, skipping"
else
  "$UV" venv "$NVIM_PY"
  "$UV" pip install --python "$NVIM_PY/bin/python3" pynvim jupyter-client ipykernel jupytext
fi
ln -sf "$NVIM_PY/bin/jupytext" "$BIN/jupytext"
# jupyter_client's KernelManager (what molten-nvim drives directly) writes the kernel's
# connection file here but never creates the directory itself - that's only done by
# full JupyterApp-based CLIs (jupyter notebook/lab), which this box never runs. Without
# it, starting any kernel fails with ENOENT on a nonexistent kernel-<uuid>.json path.
mkdir -p -m 700 "$SHARE/jupyter/runtime"

echo "==> Step 6d: ImageMagick (sixel backend for molten-nvim plot output)"
# molten-nvim's default image provider shells out to the local `wezterm` CLI, which
# doesn't exist on a plain-SSH box like this (see notebook.lua) - image.nvim's sixel
# backend is the fallback: WezTerm supports sixel directly, and it's pure terminal
# escape codes (no remote wezterm binary needed), so it survives the SSH/herdr hop
# the same way the OSC 52 clipboard does. image.nvim's magick_cli processor just
# needs the `magick`/`convert` CLI on PATH to rasterize PNGs into sixel.
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
  echo "    already installed, skipping"
elif command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get install -y imagemagick
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y ImageMagick
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y ImageMagick
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --noconfirm imagemagick
elif command -v zypper >/dev/null 2>&1; then
  $SUDO zypper install -y ImageMagick
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add imagemagick
fi
if ! { command -v magick >/dev/null 2>&1 && magick -list format 2>/dev/null | grep -qi sixel; } \
   && ! { command -v convert >/dev/null 2>&1 && convert -list format 2>/dev/null | grep -qi sixel; }; then
  echo "    warning: no SIXEL coder found in this ImageMagick build - molten plots won't render" >&2
fi

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

# omp (can1357/oh-my-pi) is intentionally not installed here - only ever build it from
# a dev checkout (e.g. /workspace/oh-my-pi), never the public release binary, to avoid
# two different `omp`s fighting over PATH. To install the dev version:
#   curl -fsSL https://bun.sh/install | bash   # bun
#   curl -fsSL https://sh.rustup.rs | sh        # cargo/rustc, needed by build:native
#   cd /workspace/oh-my-pi && bun run setup
# `bun run setup` links its own wrapper into `$(bun pm -g bin)` (usually ~/.bun/bin/omp).

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

echo "==> Step 14: sync nvim plugins and remote-plugin manifest"
# Idempotent repair, not just first-install: if a prior run of this script died
# before Step 6c finished (e.g. uv missing), a plugin manager's `build` hook -
# molten-nvim's is `:UpdateRemotePlugins` - can still fire on nvim's own
# lazy-install and write out an empty python3 manifest for lack of a python3
# provider. That stale manifest then silently sits there (nvim never redoes a
# `build` hook on its own) even after this script's later steps fix the venv,
# so every re-run re-syncs plugins and regenerates it against whatever
# python3_host_prog resolves to *now*.
timeout 300 nvim --headless "+Lazy! sync" +UpdateRemotePlugins +qa 2>&1 \
  || echo "    plugin sync failed, run ':Lazy sync' and ':UpdateRemotePlugins' yourself inside nvim"

echo "==> Done. Start a new shell (or re-ssh) to pick up zsh, then run 'herdr server' here."
echo "    From your Mac: herdr --remote <user>@<this-host>"
