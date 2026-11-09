#!/usr/bin/env bash
# SCP wrapper for VM file transfer
# Usage: scp.sh <src> <dst>
#   e.g. scp.sh scripts/tracer.sh root@localhost:/root/
#        scp.sh root@localhost:/tmp/log.txt ./

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

if [ $# -lt 2 ]; then
    error "Usage: scp.sh <src> <dst>"
    error "  e.g. scp.sh scripts/tracer.sh root@localhost:/root/"
    error "       scp.sh root@localhost:/tmp/log.txt ./"
    exit 1
fi

exec scp -P "$SSH_PORT" \
    -i "$KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "$@"
