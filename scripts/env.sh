#!/usr/bin/env bash
# linux-env: profile + vm context entry point. SOURCE ONLY.
#
# Usage:
#   source scripts/env.sh                          # ensure globals + show current
#   source scripts/env.sh --profile <name>         # enter profile
#   source scripts/env.sh --vm <name>              # enter vm (within current profile)
#   source scripts/env.sh --profile <p> --vm <v>   # enter both
#   source scripts/env.sh --reset                  # clear profile/vm scope
#
# All output messages are English. The shell-state contract is:
#   global  scope  : PRJ, SCRIPTS, CONFIGS, IMAGES, SHARE, SYZKALLER (always force-set)
#   profile scope  : PROFILE, PROFILE_SH, ARCH, LLVM, FS, [KSRC,KOBJ] | KIMAGE
#   vm      scope  : VM, VM_SH, SSH_PORT, GDB_PORT
# `$PROFILE`/`$VM` are directories; `$PROFILE_SH`/`$VM_SH` are absolute paths to
# the source-able shell files inside them.

# ---------------------------------------------------------------------------
# Shell detection + source-only enforcement
# ---------------------------------------------------------------------------
if [ -n "${ZSH_VERSION:-}" ]; then
    _envlx_self="${(%):-%x}"
elif [ -n "${BASH_VERSION:-}" ]; then
    _envlx_self="${BASH_SOURCE[0]}"
else
    echo "[env.sh] Unsupported shell. Use bash or zsh." >&2
    return 1 2>/dev/null || exit 1
fi

if [ "${_envlx_self}" = "$0" ]; then
    echo "[env.sh] This file must be sourced, not executed." >&2
    echo "         Try: source ${_envlx_self}" >&2
    return 1 2>/dev/null || exit 1
fi

# ---------------------------------------------------------------------------
# Globals (always force-export; override any pre-existing values)
# ---------------------------------------------------------------------------
export SCRIPTS="$(realpath "$(dirname "${_envlx_self}")")"
export PRJ="$(dirname "$SCRIPTS")"
export CONFIGS="$PRJ/configs"
export IMAGES="$PRJ/images"
export SHARE="$PRJ/share"
export SYZKALLER="$PRJ/syzkaller"
unset _envlx_self

# Diagnostic helpers (info/warn/error to stderr).
# shellcheck disable=SC1091
source "$SCRIPTS/.common.sh"

# ===========================================================================
# Internal helpers (re-defined every source; private prefix _envlx_)
# ===========================================================================

_envlx_unset_vm_scope() {
    unset VM VM_SH SSH_PORT GDB_PORT
}

_envlx_unset_profile_scope() {
    unset PROFILE PROFILE_SH KSRC KOBJ KIMAGE ARCH LLVM FS
}

_envlx_print_current() {
    if [ -z "${PROFILE:-}" ]; then
        echo "PROFILE: (no profile)"
    else
        echo "PROFILE:    $PROFILE"
        echo "  PROFILE_SH: ${PROFILE_SH:-(unset)}"
        echo "  ARCH:       ${ARCH:-(unset)}"
        echo "  LLVM:       ${LLVM:-(unset)}"
        echo "  FS:         ${FS:-(unset)}"
        echo "  KSRC:       ${KSRC:-(unset)}"
        echo "  KOBJ:       ${KOBJ:-(unset)}"
        echo "  KIMAGE:     ${KIMAGE:-(unset)}"
    fi
    if [ -z "${VM:-}" ]; then
        echo "VM:      (no vm)"
    else
        echo "VM:         $VM"
        echo "  VM_SH:      ${VM_SH:-(unset)}"
        echo "  SSH_PORT:   ${SSH_PORT:-(unset)}"
        echo "  GDB_PORT:   ${GDB_PORT:-(unset)}"
        local _p
        if [ -f "$VM/vm.pid" ]; then
            _p="$(cat "$VM/vm.pid" 2>/dev/null || echo "")"
            if [ -n "$_p" ] && [ -d "/proc/$_p" ]; then
                echo "  PID:        $_p (alive)"
            else
                echo "  PID:        ${_p:-(empty)} (dead)"
            fi
        else
            echo "  PID:        (no vm.pid)"
        fi
    fi

    # Restore command on its own last line: bare command, no prefix, so it
    # can be selected/copied in one go and pasted into another shell.
    if [ -n "${PROFILE:-}" ]; then
        local _restore="source \$SCRIPTS/env.sh --profile $(basename "$PROFILE")"
        if [ -n "${VM:-}" ]; then
            _restore="$_restore --vm $(basename "$VM")"
        fi
        echo
        echo "$_restore"
    fi
}

_envlx_make_template() {
    local pdir="$1"
    mkdir -p "$pdir/vms"
    cat > "$pdir/profile.sh" <<'TEMPLATE'
# linux-env profile (template)
# Required (all profiles):
export ARCH=x86_64
export LLVM=1
export FS=

# Variant A (build kernel from source) -- uncomment KSRC + KOBJ:
#export KSRC=
#export KOBJ=

# Variant B (use a prebuilt bzImage) -- uncomment KIMAGE:
#export KIMAGE=
TEMPLATE
}

# Validate that the currently-sourced profile has a coherent set of vars.
# Returns 0 on success, 1 on missing required vars.
_envlx_validate_profile() {
    local missing=()
    [ -z "${ARCH:-}" ] && missing+=("ARCH")
    [ -z "${LLVM:-}" ] && missing+=("LLVM")
    [ -z "${FS:-}" ]   && missing+=("FS")
    if [ -z "${KIMAGE:-}" ]; then
        if [ -z "${KSRC:-}" ] || [ -z "${KOBJ:-}" ]; then
            missing+=("KSRC+KOBJ or KIMAGE")
        fi
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        error "Profile is missing required vars: ${missing[*]}"
        error "Edit ${PROFILE_SH:-(unset)} and source again."
        return 1
    fi
    return 0
}

# Enter a profile by name. Returns 0 on success, 1 on validation failure,
# and 2 when a template was created (caller-friendly: nothing to do further).
_envlx_enter_profile() {
    local name="$1"
    local pdir="$PRJ/profiles/$name"
    local psh="$pdir/profile.sh"

    if [ ! -f "$psh" ]; then
        warn "Profile '$name' does not exist."
        info "Creating template at: $psh"
        _envlx_make_template "$pdir"
        info "Edit it, then run: source \$SCRIPTS/env.sh --profile $name"
        return 2
    fi

    export PROFILE="$pdir"
    export PROFILE_SH="$psh"
    # shellcheck disable=SC1090
    source "$PROFILE_SH"
    if ! _envlx_validate_profile; then
        return 1
    fi
    return 0
}

# Enter a vm by name (within current $PROFILE).
_envlx_enter_vm() {
    local name="$1"
    if [ -z "${PROFILE:-}" ]; then
        error "No profile selected. Use: source \$SCRIPTS/env.sh --profile <name>"
        return 1
    fi
    local vdir="$PROFILE/vms/$name"
    local vsh="$vdir/vm.sh"
    if [ ! -f "$vsh" ]; then
        error "VM '$name' not found at $vsh"
        error "Boot it first: \$SCRIPTS/vm.sh run $name"
        return 1
    fi
    export VM="$vdir"
    export VM_SH="$vsh"
    # shellcheck disable=SC1090
    source "$VM_SH"
    return 0
}

# ===========================================================================
# Public helpers (env.sh entry point + sibling commands)
# ===========================================================================

# `envlx`: shorthand for `source $SCRIPTS/env.sh ...`. Defined here so that
# users only have to source env.sh once at shell startup; afterwards `envlx`
# is sufficient (e.g. `envlx --profile lts-6.12 --vm a`).
envlx() {
    # shellcheck disable=SC1091
    source "$SCRIPTS/env.sh" "$@"
    return $?
}

# `vm`: dispatcher for $SCRIPTS/vm.sh. Auto-unsets vm scope after a successful
# `vm kill` / `vm rm` (which the subprocess cannot do for the parent shell).
vm() {
    "$SCRIPTS/vm.sh" "$@"
    local _rc=$?
    if [ "$_rc" -eq 0 ]; then
        case "${1:-}" in
            kill|rm) _envlx_unset_vm_scope ;;
        esac
    fi
    return $_rc
}

# ---------------------------------------------------------------------------
# FS helpers (parity with envsetup.sh; profile-context independent)
# ---------------------------------------------------------------------------

lsfs() {
    if [ ! -d "$IMAGES" ]; then
        error "Images directory not found: $IMAGES"
        return 1
    fi
    local found=0 current_name=""
    [ -n "${FS:-}" ] && current_name="$(basename "$FS")"
    local dir name img size marker status arch
    for dir in "$IMAGES"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        img="$dir/bookworm.img"
        [ -f "$img" ] || continue
        found=1
        size=$(du --apparent-size -h "$img" 2>/dev/null | cut -f1)
        marker="  "
        [ "$name" = "$current_name" ] && marker="* "
        status=""
        fuser "$img" >/dev/null 2>&1 && status=" [IN USE]"
        arch="?"
        [ -f "$dir/.arch" ] && arch=$(cat "$dir/.arch")
        printf "%s[%s] bookworm.img (%s, %s)%s\n" "$marker" "$name" "$size" "$arch" "$status"
    done
    [ "$found" -eq 0 ] && warn "No bookworm.img found under $IMAGES"
    [ -z "$current_name" ] && { echo ""; warn "FS not set"; }
}

setfs() {
    if [ -z "${1:-}" ]; then
        error "Usage: setfs <name>"
        return 1
    fi
    local target="$IMAGES/$1"
    if [ ! -d "$target" ]; then
        error "Directory not found: $target"
        lsfs
        return 1
    fi
    export FS="$target"
    info "FS: $FS"
}

mkfs() {
    local name="" arch="${ARCH:-x86_64}" size=5120 distro="bookworm"

    if [ $# -eq 0 ] || [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: mkfs <name> [-a arch] [-s size_MB] [-d distro]
  <name>       image directory name (required)
  -a, --arch   architecture (default: $ARCH)
  -s, --size   image size in MB (default: 5120)
  -d, --distro debian distribution (default: bookworm)
EOF
        return 0
    fi

    if [[ "$1" == -* ]]; then
        error "Usage: mkfs <name> [-a arch] [-s size_MB] [-d distro]"
        return 1
    fi
    name="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch)   arch="$2"; shift 2 ;;
            -s|--size)   size="$2"; shift 2 ;;
            -d|--distro) distro="$2"; shift 2 ;;
            -h|--help)   mkfs --help; return 0 ;;
            *) error "Unknown option: $1"; return 1 ;;
        esac
    done

    local img_dir="$IMAGES/$name"
    local img_file="$img_dir/$distro.img"
    if [ -f "$img_file" ]; then
        error "Image already exists: $img_file"
        return 1
    fi

    local ci_arch="$arch"
    case "$arch" in
        arm64)  ci_arch="aarch64" ;;
        amd64)  ci_arch="x86_64"  ;;
    esac

    info "Creating filesystem image: images/$name/  (arch=$ci_arch, distro=$distro, size=${size}MB)"
    mkdir -p "$img_dir"
    echo "$ci_arch" > "$img_dir/.arch"

    local prev_dir="$PWD"
    if ! ( cd "$img_dir" && sudo "$SCRIPTS/create-image.sh" -a "$ci_arch" -d "$distro" -s "$size" ); then
        error "create-image.sh failed"
        return 1
    fi

    sudo chown "$(id -u):$(id -g)" "$img_dir"/* 2>/dev/null || true
    if [ -d "$img_dir/$distro" ]; then
        info "Cleaning up debootstrap directory..."
        sudo rm -rf "$img_dir/$distro"
    fi

    if [ ! -f "$img_file" ]; then
        error "Image file not created: $img_file"
        return 1
    fi
    info "Created: images/$name/$distro.img"
    setfs "$name"
}

vmhttp() {
    local dir="${1:-${SHARE:-.}}"
    local port="${2:-8888}"
    if [ ! -d "$dir" ]; then
        error "Directory not found: $dir"
        return 1
    fi
    dir="$(realpath "$dir")"
    info "Serving $dir on port $port"
    info "From guest: curl -O 10.0.2.2:$port/<filename>"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir"
}

# ===========================================================================
# Argument parsing
# ===========================================================================

_envlx_profile_arg=""
_envlx_vm_arg=""
_envlx_reset=0
_envlx_no_args=1

while [ $# -gt 0 ]; do
    _envlx_no_args=0
    case "$1" in
        --profile)
            if [ "$#" -lt 2 ]; then
                error "--profile requires <name>"
                unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
                return 1
            fi
            _envlx_profile_arg="$2"
            shift 2
            ;;
        --vm)
            if [ "$#" -lt 2 ]; then
                error "--vm requires <name>"
                unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
                return 1
            fi
            _envlx_vm_arg="$2"
            shift 2
            ;;
        --reset)
            _envlx_reset=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: source env.sh [args]
  --profile <name>            enter profile
  --vm <name>                 enter vm (requires profile context)
  --profile <p> --vm <v>      enter both at once
  --reset                     clear profile/vm scope (keep globals)
  (no args)                   show current context
EOF
            unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
            return 0
            ;;
        *)
            error "Unknown argument: $1"
            unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
            return 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if [ "$_envlx_no_args" -eq 1 ]; then
    # Refresh from on-disk metadata so stale shell state (e.g. SSH_PORT from a
    # prior `vm run vm1` that was later killed and re-run) is replaced with the
    # current vm.sh / profile.sh values.
    if [ -n "${PROFILE_SH:-}" ] && [ -f "$PROFILE_SH" ]; then
        # shellcheck disable=SC1090
        source "$PROFILE_SH"
    fi
    if [ -n "${VM_SH:-}" ] && [ -f "$VM_SH" ]; then
        # shellcheck disable=SC1090
        source "$VM_SH"
    fi
    _envlx_print_current
    unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
    return 0
fi

if [ "$_envlx_reset" -eq 1 ]; then
    _envlx_unset_vm_scope
    _envlx_unset_profile_scope
    info "Cleared profile + vm scope (globals preserved)."
    unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
    return 0
fi

# Always unset → set discipline.
# NB: callers may have `set -e` enabled; capture function return codes via
# `if ...; then ... else _rc=$? fi` so errexit doesn't trip on non-zero returns.
if [ -n "$_envlx_profile_arg" ]; then
    _envlx_unset_vm_scope
    _envlx_unset_profile_scope
    if _envlx_enter_profile "$_envlx_profile_arg"; then
        _envlx_rc=0
    else
        _envlx_rc=$?
    fi
    case "$_envlx_rc" in
        0) ;;                                                 # ok, may proceed to vm
        2) unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc; return 0 ;;  # template created
        *) unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc; return 1 ;;
    esac
fi

if [ -n "$_envlx_vm_arg" ]; then
    _envlx_unset_vm_scope
    if _envlx_enter_vm "$_envlx_vm_arg"; then
        :
    else
        unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc
        return 1
    fi
fi

_envlx_print_current
unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc
return 0
