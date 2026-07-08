#!/usr/bin/env bash
# SSH wrapper for VM connection
# Usage: ssh.sh [additional ssh args...]

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/.common.sh"

if [ -z "$SSH_PORT" ]; then
    error "SSH_PORT not set. Run 'source scripts/envsetup.sh' first."
    exit 1
fi

if [ -z "$FS" ]; then
    error "FS not set. Run 'setfs <name>' first."
    exit 1
fi

KEY="$FS/bookworm.id_rsa"
if [ ! -f "$KEY" ]; then
    error "SSH key not found: $KEY"
    exit 1
fi

SSH_OPTS=(
    -p "$SSH_PORT"
    -i "$KEY"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
)

# Force pty when running a remote command, so the remote process's stdout is
# line-buffered (default fully-buffered mode hides output of programs that
# crash/panic before flushing — e.g. kernel exploit binaries).
if [ "$#" -gt 0 ]; then
    SSH_OPTS+=(-t)
fi

exec ssh "${SSH_OPTS[@]}" root@localhost "$@"
