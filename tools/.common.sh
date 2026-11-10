# Shared by the Bash CLIs and the Bash/zsh interactive environment.
# Resolve paths from this file, never from inherited project variables or cwd.
if [ -n "${ZSH_VERSION:-}" ]; then
    _kenv_common_self="${(%):-%x}"
else
    _kenv_common_self="${BASH_SOURCE[0]}"
fi
export SCRIPTS="$(dirname "$(realpath "$_kenv_common_self")")"
export PRJ="$(dirname "$SCRIPTS")"
export CONFIGS="$PRJ/configs"
export IMAGES="$PRJ/images"
export SHARE="$PRJ/share"
export SYZKALLER="$PRJ/syzkaller"
unset _kenv_common_self

INFO='\033[1;36m'  # Cyan (info color)
WARN='\033[1;33m'  # Yellow (warning color)
ERROR='\033[1;31m' # Red (error color)
RESET='\033[0m'     # Reset to default color

# Diagnostic helpers go to stderr so stdout stays clean for callers that want
# to capture machine-readable output (e.g. vm.sh ls --json).
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

validate_scope_name() {
    local kind="$1" value="$2"
    if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        error "$kind must contain only letters, digits, '.', '_' or '-', and start with a letter or digit: $value"
        return 1
    fi
}

clear_vm_scope() {
    unset VM VM_SH SSH_PORT GDB_PORT
    unset VM_STARTED_AT VM_KERNEL_IMAGE VM_VMLINUX VM_KSRC VM_KOBJ VM_FS VM_LOG
}

clear_profile_scope() {
    unset PROFILE PROFILE_SH ARCH LLVM FS KSRC KOBJ KIMAGE CROSS_COMPILE
    unset SMP MEM EXTRA_CMDLINE
}

load_profile() {
    local name="$1" file
    validate_scope_name "Profile name" "$name" || return 2
    file="$PRJ/profiles/$name/profile.sh"
    if [ ! -f "$file" ]; then
        error "profile.sh missing: $file"
        return 1
    fi
    clear_vm_scope
    clear_profile_scope
    export PROFILE="$PRJ/profiles/$name" PROFILE_SH="$file"
    # Profiles are trusted user-authored shell configuration.
    source "$file" || { clear_profile_scope; return 1; }
}

load_vm() {
    local name="$1" file
    validate_scope_name "VM name" "$name" || return 2
    if [ -z "${PROFILE:-}" ]; then
        error "VM selection requires a profile"
        return 2
    fi
    file="$PROFILE/vms/$name/vm.sh"
    if [ ! -f "$file" ]; then
        error "VM metadata missing: $file"
        return 1
    fi
    clear_vm_scope
    export VM="$PROFILE/vms/$name" VM_SH="$file"
    source "$file" || { clear_vm_scope; return 1; }
    # Connections use the image and sources captured at boot, even if the
    # profile was edited while the VM was running. Support older metadata too.
    [ -z "${VM_FS+x}" ] || export FS="$VM_FS"
    [ -z "${VM_KSRC+x}" ] || export KSRC="$VM_KSRC"
    [ -z "${VM_KOBJ+x}" ] || export KOBJ="$VM_KOBJ"
    return 0
}
