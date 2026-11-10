#!/usr/bin/env bash
# linux-env: profile + vm context entry point. SOURCE ONLY.
#
# Usage:
#   source tools/env.sh                          # ensure globals + show current
#   source tools/env.sh --profile <name>         # enter profile
#   source tools/env.sh --vm <name>              # enter vm (within current profile)
#   source tools/env.sh --profile <p> --vm <v>   # enter both
#   source tools/env.sh --reset                  # clear profile/vm scope
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
# Load paths and scope helpers without changing the caller's shell options.
# ---------------------------------------------------------------------------
source "$(dirname "$(realpath "$_envlx_self")")/.common.sh"
unset _envlx_self

# ===========================================================================
# Internal helpers (re-defined every source; private prefix _envlx_)
# ===========================================================================

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
        local _restore="source $(printf '%q' "$SCRIPTS/env.sh") --profile $(basename "$PROFILE")"
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
export LLVM=19
export FS=$IMAGES/x64

# Variant A (build kernel from source) -- uncomment KSRC + KOBJ:
#export KSRC="$PRJ/kernels/..."
#export KOBJ="$KSRC/build/debug"

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
    validate_scope_name "Profile name" "$name" || return 1
    local pdir="$PRJ/profiles/$name"
    local psh="$pdir/profile.sh"

    if [ ! -f "$psh" ]; then
        warn "Profile '$name' does not exist."
        info "Creating template at: $psh"
        _envlx_make_template "$pdir" || return 1
        info "Edit it, then run: source \$SCRIPTS/env.sh --profile $name"
        return 2
    fi

    load_profile "$name" || return 1
    if ! _envlx_validate_profile; then
        clear_profile_scope
        return 1
    fi
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

# `vm`: human-facing shim around $SCRIPTS/vm.sh. Auto-injects -p/-v from the
# current shell's $PROFILE/$VM (env.sh contract) so users don't have to retype
# them. vm.sh itself is strict and ignores inherited env; the explicit flags
# come from here.
#
# Optional leading `-p <profile>` / `-v <vm>` flags (before the subcommand)
# override the current scope for that single call only — the shell's
# $PROFILE/$VM are left untouched (one-shot). Example:
#   vm -p kctf-6.12.67 -v vm1 ssh -- uname -a
#
# Translation per subcommand (P/V = effective profile/vm: override else scope):
#   vm ls / ps / help          → vm.sh ls / ps / help                 (no flags)
#   vm run <name> [opts]       → vm.sh -p P run <name> [opts]         (needs P)
#   vm -v <name> run [opts]    → vm.sh -p P run <name> [opts]         (==above; both = error)
#   vm rm <name>               → vm.sh -p P -v <name> rm             (positional → -v)
#   vm ssh|scp|gdb|attach|kill|log [args] →
#                                vm.sh -p P -v V <subcmd> [args]      (needs P+V)
#
# After a successful operation on the VM in this shell's scope, the shim
# unsets vm-scope env vars (subprocess vm.sh cannot do that for the parent):
#   - `vm kill`                  → unset (when killing the current $VM)
#   - `vm rm <name>` where <name> matches $(basename "$VM") → unset.
# An override that targets a different profile/vm never touches the scope.
vm() {
    # Optional leading -p/-v overrides (must precede the subcommand). One-shot:
    # they only change flags forwarded to vm.sh; $PROFILE/$VM scope is untouched.
    local _p_override="" _v_override=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -p|--profile)
                [ "$#" -lt 2 ] && { error "vm: -p requires <profile>"; return 2; }
                _p_override="$2"; shift 2 ;;
            -v|--vm)
                [ "$#" -lt 2 ] && { error "vm: -v requires <vm>"; return 2; }
                _v_override="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    # Effective names: override wins, else current shell scope.
    local _p="$_p_override"
    [ -z "$_p" ] && [ -n "${PROFILE:-}" ] && _p="$(basename "$PROFILE")"
    local _v="$_v_override"
    # A one-shot profile override must not reuse a VM from a different profile.
    if [ -z "$_v" ] && [ -n "${VM:-}" ] && [ -n "${PROFILE:-}" ] \
       && [ "$_p" = "$(basename "$PROFILE")" ]; then
        _v="$(basename "$VM")"
    fi

    local subcmd="${1:-}"
    if [ -z "$subcmd" ]; then
        "$SCRIPTS/vm.sh" help
        return $?
    fi
    local _rc=0
    case "$subcmd" in
        ls|ps|help|-h|--help)
            "$SCRIPTS/vm.sh" "$@" || _rc=$?
            ;;
        run)
            if [ -z "$_p" ]; then
                error "vm run: no profile; pass -p <name> or run \`envlx --profile <name>\` first"
                return 2
            fi
            shift
            # -v override supplies the run target name; a positional name also
            # works, but both at once is ambiguous.
            local _has_pos=0 _a
            for _a in "$@"; do
                case "$_a" in -*) ;; *) _has_pos=1; break ;; esac
            done
            if [ -n "$_v_override" ] && [ "$_has_pos" -eq 1 ]; then
                error "vm run: both -v <name> and a positional name given; use one"
                return 2
            fi
            if [ -n "$_v_override" ]; then
                "$SCRIPTS/vm.sh" -p "$_p" run "$_v_override" "$@" || _rc=$?
            else
                "$SCRIPTS/vm.sh" -p "$_p" run "$@" || _rc=$?
            fi
            ;;
        rm)
            if [ -z "$_p" ]; then
                error "vm rm: no profile; pass -p <name> or run \`envlx --profile <name>\` first"
                return 2
            fi
            shift
            local _target="${1:-}"
            [ -n "$_target" ] && shift
            if [ -n "$_v_override" ]; then
                if [ -n "$_target" ]; then
                    error "vm rm: both -v <name> and a positional name given; use one"
                    return 2
                fi
                _target="$_v_override"
            fi
            if [ -z "$_target" ]; then
                error "usage: vm [-p <profile>] rm <vm_name>   (or -v <vm_name>)"
                return 2
            fi
            "$SCRIPTS/vm.sh" -p "$_p" -v "$_target" rm "$@" || _rc=$?
            # Only unset shell scope if we removed the VM the scope points to.
            if [ "$_rc" -eq 0 ] && [ -n "${PROFILE:-}" ] && [ -n "${VM:-}" ] \
               && [ "$_p" = "$(basename "$PROFILE")" ] && [ "$_target" = "$(basename "$VM")" ]; then
                clear_vm_scope
            fi
            ;;
        ssh|scp|gdb|attach|kill|log)
            if [ -z "$_p" ] || [ -z "$_v" ]; then
                error "vm $subcmd: no profile/vm; pass -p <p> -v <v> or run \`envlx --profile <p> --vm <v>\` first"
                return 2
            fi
            shift
            "$SCRIPTS/vm.sh" -p "$_p" -v "$_v" "$subcmd" "$@" || _rc=$?
            if [ "$_rc" -eq 0 ] && [ "$subcmd" = "kill" ] && [ -n "${PROFILE:-}" ] && [ -n "${VM:-}" ] \
               && [ "$_p" = "$(basename "$PROFILE")" ] && [ "$_v" = "$(basename "$VM")" ]; then
                clear_vm_scope
            fi
            ;;
        *)
            local _flags=()
            [ -n "$_p_override" ] && _flags+=(-p "$_p_override")
            [ -n "$_v_override" ] && _flags+=(-v "$_v_override")
            "$SCRIPTS/vm.sh" "${_flags[@]}" "$@" || _rc=$?
            ;;
    esac
    return $_rc
}

# `kernel`: human-facing shim around $SCRIPTS/kernel.sh. Auto-injects -p from
# the current $PROFILE so users don't have to retype it.
kernel() {
    if [ "$#" -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] \
       || [ "${1:-}" = "-p" ] || [ "${1:-}" = "--profile" ]; then
        "$SCRIPTS/kernel.sh" "$@"
        return $?
    fi
    if [ -z "${PROFILE:-}" ]; then
        error "kernel: no \$PROFILE; run \`envlx --profile <name>\` first"
        return 2
    fi
    "$SCRIPTS/kernel.sh" -p "$(basename "$PROFILE")" "$@"
}

# Connect using the bundled certificate; independent of profile/VM selection.
connect() { "$SCRIPTS/connect.sh" "$@"; }

# ---------------------------------------------------------------------------
# Image helpers: implementation lives in fs.sh for direct CLI use too.
# ---------------------------------------------------------------------------

lsfs() { "$SCRIPTS/fs.sh" ls "$@"; }

setfs() {
    if [ "$#" -ne 1 ]; then
        error "Usage: setfs <name>"; return 2
    fi
    validate_scope_name "Image name" "$1" || return 2
    local target="$IMAGES/$1"
    if [ ! -d "$target" ]; then
        error "Directory not found: $target"; return 1
    fi
    export FS="$target"
    info "FS: $FS (shell only; edit profile.sh to change VM images)"
}

mkfs() {
    # Keep the familiar interactive name without duplicating creation logic.
    local arg
    for arg in "$@"; do
        case "$arg" in -h|--help) "$SCRIPTS/fs.sh" create --help; return $? ;; esac
    done
    if [ "$#" -eq 0 ]; then "$SCRIPTS/fs.sh" create --help; return $?; fi
    local name="$1"
    shift
    "$SCRIPTS/fs.sh" create "$name" -a "${ARCH:-x86_64}" "$@" || return $?
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
        -p|--profile)
            if [ "$#" -lt 2 ]; then
                error "-p/--profile requires <name>"
                unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
                return 1
            fi
            _envlx_profile_arg="$2"
            shift 2
            ;;
        -v|--vm)
            if [ "$#" -lt 2 ]; then
                error "-v/--vm requires <name>"
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
Usage: source env.sh [args]   (a.k.a. envlx [args])
  -p, --profile <name>        enter profile
  -v, --vm <name>             enter vm (requires profile context)
  -p <p> -v <v>               enter both at once
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
    _envlx_saved_profile="${PROFILE:-}"
    _envlx_saved_profile="${_envlx_saved_profile##*/}"
    _envlx_saved_vm="${VM:-}"
    _envlx_saved_vm="${_envlx_saved_vm##*/}"
    if [ -n "$_envlx_saved_profile" ]; then
        clear_vm_scope
        clear_profile_scope
        if ! load_profile "$_envlx_saved_profile"; then
            unset _envlx_saved_profile _envlx_saved_vm
            return 1
        fi
        if [ -n "$_envlx_saved_vm" ]; then
            if ! load_vm "$_envlx_saved_vm"; then
                unset _envlx_saved_profile _envlx_saved_vm
                return 1
            fi
        fi
    fi
    unset _envlx_saved_profile _envlx_saved_vm
    _envlx_print_current
    unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
    return 0
fi

if [ "$_envlx_reset" -eq 1 ]; then
    clear_vm_scope
    clear_profile_scope
    info "Cleared profile + vm scope (globals preserved)."
    unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args
    return 0
fi

# Always unset → set discipline.
# NB: callers may have `set -e` enabled; capture function return codes via
# `if ...; then ... else _rc=$? fi` so errexit doesn't trip on non-zero returns.
if [ -n "$_envlx_profile_arg" ]; then
    clear_vm_scope
    clear_profile_scope
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
    clear_vm_scope
    if load_vm "$_envlx_vm_arg"; then
        :
    else
        unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc
        return 1
    fi
fi

_envlx_print_current
unset _envlx_profile_arg _envlx_vm_arg _envlx_reset _envlx_no_args _envlx_rc
return 0
