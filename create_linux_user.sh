#!/usr/bin/env bash
# Creates a normal (non-root) Linux user with passwordless sudo inside a
# container that only has root, so that `claude --dangerously-skip-permissions`
# can run - Claude Code refuses that flag when the effective user is root.
#
# Usage (as root):   ./create_linux_user.sh
# Then:              su - eungizoa      # login shell, drops the root env
#                    cc                 # alias for claude --dangerously-skip-permissions
#
# Beyond the user itself, this copies over just enough of root's Claude Code
# install for the new user to start already logged in (same OAuth token, same
# onboarding state). The full shell/toolchain setup still comes from
# bootstrap-linux.sh, which is safe to run as the new user afterwards.
#
# Re-run any time; every step is idempotent and never clobbers state the new
# user already has.
set -euo pipefail

USERNAME="${USERNAME:-eungizoa}"
# Optional: USER_PASSWORD=... to set a login password (needed only for ssh/`su`
# *from* the new user; `su - <user>` from root and sudo never ask for one).
# Optional: USER_UID / USER_GID to override the ids picked in Step 2.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_HOME="$(getent passwd 0 | cut -d: -f6)"  # where the existing root setup lives

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root (it creates a user and edits /etc/sudoers.d)." >&2
  exit 1
fi

echo "==> Step 1: sudo via the system package manager"
if command -v sudo >/dev/null 2>&1; then
  echo "    sudo already installed, skipping"
elif command -v apt-get >/dev/null 2>&1; then
  # Minimal images often ship without sudo and with stale/absent apt lists.
  apt-get install -y sudo || { apt-get update -y && apt-get install -y sudo; }
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y sudo
elif command -v yum >/dev/null 2>&1; then
  yum install -y sudo
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm sudo
elif command -v zypper >/dev/null 2>&1; then
  zypper install -y sudo
elif command -v apk >/dev/null 2>&1; then
  apk add sudo
else
  echo "    No known package manager found; install sudo yourself, then re-run this script." >&2
  exit 1
fi

echo "==> Step 2: pick uid/gid"
# Bind-mounted work trees are owned by the host's uid. Matching it means the new
# user can write them without any chown of the mount itself.
TARGET_UID="${USER_UID:-$(stat -c %u "$DIR")}"
TARGET_GID="${USER_GID:-$(stat -c %g "$DIR")}"
if [ "$TARGET_UID" = 0 ]; then
  TARGET_UID=""  # repo is root-owned; nothing to match, let useradd choose
  TARGET_GID=""
else
  taken="$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)"
  if [ -n "$taken" ] && [ "$taken" != "$USERNAME" ]; then
    echo "    uid $TARGET_UID is already '$taken'; letting useradd choose instead"
    TARGET_UID=""
  fi
fi
echo "    uid=${TARGET_UID:-auto} gid=${TARGET_GID:-auto} (owner of $DIR)"

echo "==> Step 3: user '$USERNAME'"
GROUP_NAME="$USERNAME"
if [ -n "$TARGET_GID" ] && existing_group="$(getent group "$TARGET_GID" | cut -d: -f1)" && [ -n "$existing_group" ]; then
  GROUP_NAME="$existing_group"  # gid already claimed - join that group rather than fail
elif ! getent group "$GROUP_NAME" >/dev/null; then
  groupadd ${TARGET_GID:+-g "$TARGET_GID"} "$GROUP_NAME"
fi

# Match root's shell so the environment feels the same; bootstrap-linux.sh
# Step 12 is what fills in the real ~/.zshrc later.
LOGIN_SHELL=/bin/bash
[ -x /bin/zsh ] && LOGIN_SHELL=/bin/zsh

if getent passwd "$USERNAME" >/dev/null; then
  echo "    already exists, skipping useradd"
else
  useradd --create-home --shell "$LOGIN_SHELL" --gid "$GROUP_NAME" \
    ${TARGET_UID:+--uid "$TARGET_UID"} "$USERNAME"
fi
HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
echo "    home=$HOME_DIR shell=$LOGIN_SHELL group=$GROUP_NAME"

# Owner-aware mkdir, so every directory this script creates in the new home
# belongs to the new user rather than to root.
mk_user_dir() { install -d -m 0755 -o "$USERNAME" -g "$GROUP_NAME" "$@"; }

echo "==> Step 4: sudo rights"
for admin_group in sudo wheel; do
  if getent group "$admin_group" >/dev/null; then
    usermod -aG "$admin_group" "$USERNAME"
    echo "    added to '$admin_group'"
  fi
done
# Passwordless, because the account has no password at all (see Step 5) - a
# password-prompting sudo would be unusable. Validated in a temp file first: a
# malformed drop-in breaks sudo for everyone, including this script's next run.
mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d
SUDOERS_TMP="$(mktemp)"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" > "$SUDOERS_TMP"
if command -v visudo >/dev/null 2>&1 && ! visudo -cqf "$SUDOERS_TMP"; then
  rm -f "$SUDOERS_TMP"
  echo "    generated sudoers rule failed validation; aborting" >&2
  exit 1
fi
install -m 0440 -o root -g root "$SUDOERS_TMP" "/etc/sudoers.d/$USERNAME"
rm -f "$SUDOERS_TMP"
echo "    /etc/sudoers.d/$USERNAME written (NOPASSWD)"

echo "==> Step 5: password"
if [ -n "${USER_PASSWORD:-}" ]; then
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
  echo "    set from \$USER_PASSWORD"
else
  echo "    left unset - reach the account with 'su - $USERNAME' as root"
fi

echo "==> Step 6: Claude Code binary"
mk_user_dir "$HOME_DIR/.local" "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share"
SRC_CLAUDE="$(readlink -f "$ROOT_HOME/.local/bin/claude" 2>/dev/null || true)"
if [ -n "$SRC_CLAUDE" ] && [ -x "$SRC_CLAUDE" ]; then
  # Reuse root's copy instead of re-downloading ~275MB. The native installer's
  # layout is versions/<tag> plus a bin symlink, kept here so `claude update`
  # keeps working for the new user. A hardlink shares root's inode (mode 0755,
  # so world-readable/executable); cp is the fallback across filesystems.
  CLAUDE_VERSION="$(basename "$SRC_CLAUDE")"
  mk_user_dir "$HOME_DIR/.local/share/claude" "$HOME_DIR/.local/share/claude/versions"
  DEST_CLAUDE="$HOME_DIR/.local/share/claude/versions/$CLAUDE_VERSION"
  if [ ! -e "$DEST_CLAUDE" ]; then
    ln "$SRC_CLAUDE" "$DEST_CLAUDE" 2>/dev/null || cp -p "$SRC_CLAUDE" "$DEST_CLAUDE"
  fi
  ln -sfn "$DEST_CLAUDE" "$HOME_DIR/.local/bin/claude"
  chown -h "$USERNAME:$GROUP_NAME" "$HOME_DIR/.local/bin/claude"
  echo "    linked $CLAUDE_VERSION from root's install"
else
  echo "    root has no Claude Code install to share; run this as $USERNAME:"
  echo "      curl -fsSL https://claude.ai/install.sh | bash"
fi
# jq is what the statusLine command in home/.claude/settings.json shells out to;
# without it the status line renders empty.
for tool in jq; do
  if [ -x "$ROOT_HOME/.local/bin/$tool" ] && [ ! -e "$HOME_DIR/.local/bin/$tool" ]; then
    ln "$ROOT_HOME/.local/bin/$tool" "$HOME_DIR/.local/bin/$tool" 2>/dev/null \
      || cp -p "$ROOT_HOME/.local/bin/$tool" "$HOME_DIR/.local/bin/$tool"
    echo "    linked $tool from root's install"
  fi
done

echo "==> Step 7: Claude Code credentials and config"
mk_user_dir "$HOME_DIR/.claude"
# Copied only when absent, so a re-run never overwrites a token the new user
# refreshed themselves. .claude.json also carries the onboarding/trust flags,
# which is what keeps the first launch from re-prompting.
for rel in .claude.json .claude/.credentials.json; do
  if [ -f "$ROOT_HOME/$rel" ] && [ ! -e "$HOME_DIR/$rel" ]; then
    install -m 0600 -o "$USERNAME" -g "$GROUP_NAME" "$ROOT_HOME/$rel" "$HOME_DIR/$rel"
    echo "    copied $rel"
  fi
done
# The two Claude entries from bootstrap-linux.sh Step 11, so the new user gets
# the same global settings and CLAUDE.md. That script remains the source of
# truth - running it as $USERNAME adds the rest (nvim, codex, opencode, omp).
for pair in "home/.claude/settings.json:.claude/settings.json" "home/AGENTS.md:.claude/CLAUDE.md"; do
  src="$DIR/${pair%%:*}"
  dest="$HOME_DIR/${pair##*:}"
  if [ -e "$src" ] && { [ ! -e "$dest" ] || [ -L "$dest" ]; }; then
    ln -sfn "$src" "$dest"
    chown -h "$USERNAME:$GROUP_NAME" "$dest"
    echo "    linked ${pair##*:} -> $src"
  fi
done

echo "==> Step 8: shell environment"
if [ "$LOGIN_SHELL" = /bin/zsh ]; then
  # PATH goes in .zshenv, not .zshrc: zsh only reads .zshrc for *interactive*
  # shells, so `su - $USERNAME -c claude` would not find the binary otherwise.
  if [ ! -e "$HOME_DIR/.zshenv" ]; then
    cat > "$HOME_DIR/.zshenv" <<'EOF'
# Written by create_linux_user.sh. Kept separate from .zshrc so that
# non-interactive shells (su -c, ssh <cmd>, scripts) also find ~/.local/bin.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
    chown "$USERNAME:$GROUP_NAME" "$HOME_DIR/.zshenv"
    echo "    ~/.zshenv written"
  else
    echo "    ~/.zshenv already present, skipping"
  fi
  # Deliberately tiny: root's .zshrc sources fnm/starship/zsh plugins that live
  # under root's inaccessible $HOME. bootstrap-linux.sh Step 12 overwrites this
  # with the full version once its dependencies exist for this user.
  if [ ! -e "$HOME_DIR/.zshrc" ]; then
    cat > "$HOME_DIR/.zshrc" <<'EOF'
export EDITOR=vi
autoload -Uz compinit && compinit
alias cc="claude --dangerously-skip-permissions"

# Placeholder written by create_linux_user.sh. Run bootstrap-linux.sh from the
# dotfiles checkout to replace it with the full configuration.
EOF
    chown "$USERNAME:$GROUP_NAME" "$HOME_DIR/.zshrc"
    echo "    ~/.zshrc written"
  else
    echo "    ~/.zshrc already present, skipping"
  fi
else
  # Ubuntu/Debian's skel .profile already prepends ~/.local/bin for bash.
  echo "    login shell is $LOGIN_SHELL; relying on its skel dotfiles"
fi

echo "==> Step 9: hand root-created files in $DIR to $USERNAME"
# Anything a root Claude Code session wrote into the checkout (.claude/,
# git objects) would otherwise be read-only for the new user.
STRAYS="$(find "$DIR" -uid 0 -print -quit)"
if [ -n "$STRAYS" ]; then
  find "$DIR" -uid 0 -exec chown "$USERNAME:$GROUP_NAME" {} +
  echo "    done"
else
  echo "    nothing root-owned, skipping"
fi

cat <<EOF

Done. Next:

  su - $USERNAME
  cd $DIR
  claude --dangerously-skip-permissions    # or: cc

Use 'su -' (with the dash) so the login shell drops root's environment.
Other work trees under /workspace that root created are not covered by Step 9;
chown them the same way if you hit permission errors:

  chown -R $USERNAME:$GROUP_NAME /workspace/<dir>

For the full shell and toolchain (zsh plugins, node/fnm, neovim, starship),
run ./bootstrap-linux.sh as $USERNAME.
EOF
