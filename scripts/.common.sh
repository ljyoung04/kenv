INFO='\033[1;36m'  # Cyan (info color)
WARN='\033[1;33m'  # Yellow (warning color)
ERROR='\033[1;31m' # Red (error color)
RESET='\033[0m'     # Reset to default color

# Diagnostic helpers go to stderr so stdout stays clean for callers that want
# to capture machine-readable output (e.g. `eval $(run-vm.sh)`).
info() {
    echo -e "[*] ${INFO}$1${RESET}" >&2
}
warn() {
    echo -e "[!] ${WARN}$1${RESET}" >&2
}

error() {
    echo -e "[-] ${ERROR}$1${RESET}" >&2
}

check_port_available() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}
