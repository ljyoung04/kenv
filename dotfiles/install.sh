#!/bin/bash
# Runs during Docker build to install tools into /etc/skel
set -e

SKEL="/etc/skel"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# 1) oh-my-bash
# ──────────────────────────────────────────────────────────────────────────────
git clone --depth=1 https://github.com/ohmybash/oh-my-bash.git /opt/oh-my-bash

# ──────────────────────────────────────────────────────────────────────────────
# 2) bata24/gef
# ──────────────────────────────────────────────────────────────────────────────
git clone --depth=1 https://github.com/bata24/gef.git /opt/gef

# ──────────────────────────────────────────────────────────────────────────────
# 3) smart-bash-history
# ──────────────────────────────────────────────────────────────────────────────
git clone --depth=1 https://github.com/jan-warchol/smart-bash-history.git /opt/smart-bash-history
# Fix: use 'command cp' to bypass cp -i alias
sed -i 's/\[ -e $HISTFILE \] && cp $HISTFILE/[ -e $HISTFILE ] \&\& command cp $HISTFILE/' /opt/smart-bash-history/backup.sh

# ──────────────────────────────────────────────────────────────────────────────
# 4) oh-my-tmux
# ──────────────────────────────────────────────────────────────────────────────
git clone --depth=1 https://github.com/gpakosz/.tmux.git /opt/oh-my-tmux
ln -sf /opt/oh-my-tmux/.tmux.conf "$SKEL/.tmux.conf"
command cp "$SCRIPT_DIR/.tmux.conf.local" "$SKEL/.tmux.conf.local"

# ──────────────────────────────────────────────────────────────────────────────
# 5) zoxide
# ──────────────────────────────────────────────────────────────────────────────
curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
# install.sh puts binary in ~/.local/bin; move to system path
mv /root/.local/bin/zoxide /usr/local/bin/zoxide 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# 6) Copy dotfiles to /etc/skel
# ──────────────────────────────────────────────────────────────────────────────
command cp "$SCRIPT_DIR/.bashrc"       "$SKEL/.bashrc"
command cp "$SCRIPT_DIR/.bash_aliases" "$SKEL/.bash_aliases"
command cp "$SCRIPT_DIR/.gdbinit"      "$SKEL/.gdbinit"

echo "[+] dotfiles install complete"
