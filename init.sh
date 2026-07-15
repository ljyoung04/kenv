#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="${SCRIPT_DIR}/${ENV_FILE}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# --- Detect UID/GID/USER ---
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(whoami)"

# --- Find available SSH port in 2000-3000 ---
find_available_port() {
    local port
    for port in $(shuf -i 2000-3000 -n 1001); do
        if ! ss -tlnH "sport = :${port}" 2>/dev/null | grep -q .; then
            echo "$port"
            return 0
        fi
    done
    # Fallback
    echo "2222"
}

SSH_PORT="$(find_available_port)"

# --- Check existing .env ---
if [[ -f "$ENV_PATH" ]]; then
    warn ".env already exists:"
    echo "  $(cat "$ENV_PATH" | tr '\n' ' ')"
    echo
    read -rp "Overwrite? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi
fi

# --- Write .env ---
cat > "$ENV_PATH" <<EOF
HOST_UID=${HOST_UID}
HOST_GID=${HOST_GID}
HOST_USER=${HOST_USER}
SSH_PORT=${SSH_PORT}
EOF

info "Generated ${ENV_FILE}:"
echo "  HOST_UID=${HOST_UID}"
echo "  HOST_GID=${HOST_GID}"
echo "  HOST_USER=${HOST_USER}"
echo "  SSH_PORT=${SSH_PORT}"
