#!/usr/bin/env bash

# Detect shell (Bash/Zsh compatibility)
if [ -n "$ZSH_VERSION" ]; then
    _SCRIPT_SOURCE="${(%):-%x}"
elif [ -n "$BASH_VERSION" ]; then
    _SCRIPT_SOURCE="${BASH_SOURCE[0]}"
else
    echo "Unsupported shell. Please use bash or zsh."
    return 1
fi

if [[ "$_SCRIPT_SOURCE" == "$0" ]]; then
    echo "Usage: SRC=.. OBJ=.. source env.sh"
    return 1
fi

export SCRIPTS="$(realpath "$(dirname "$_SCRIPT_SOURCE")")"
export PRJ="$(dirname "$SCRIPTS")"
export FILEPATH_ENV="$HOME/.linux.env"

unset _READY
source "$SCRIPTS/.common.sh"

export DEF_ARCH="x86_64"
export DEF_CC="llvm-19"
export DEF_SSH_PORT=20202
export DEF_GDB_PORT=1245
export IMAGES="$PRJ/images"
export CONFIGS="$PRJ/configs"

# ──────────────────────────────────────────────────────────────────────────────
# 1) ARCH setup
# ──────────────────────────────────────────────────────────────────────────────
if [ -z "$ARCH" ] || [ "$ARCH" == "" ]; then
    ARCH="$DEF_ARCH"
fi

_ARCH="$ARCH"
unset ARCH
export ARCH="$_ARCH"

if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "arm64" ]; then
    error "Error: ARCH not supported: $ARCH"
    return 1
fi

export SHARE="$PRJ/share"
export RANDOMS="$PRJ/randoms"
export SYZKALLER="$PRJ/syzkaller"
export PATCHES="$PRJ/patches"

# commands

function current() {
    CMD="ARCH=$ARCH CC=$CC KSRC=$KSRC KOBJ=$KOBJ FS=$FS SSH_PORT=$SSH_PORT GDB_PORT=$GDB_PORT source $SCRIPTS/envsetup.sh"
    info "ARCH:     $ARCH"
    info "CC:       $CC"
    info "KSRC:     $KSRC"
    info "KOBJ:     $KOBJ"
    info "FS:       $FS"
    info "SSH_PORT: $SSH_PORT"
    info "GDB_PORT: $GDB_PORT"
    info "$CMD"
    warn "Run 'source ~/$(basename "$FILEPATH_ENV")' to restore this environment"
    echo "current_reset" >| "$FILEPATH_ENV"
    echo "$CMD" >> "$FILEPATH_ENV"
    # echo "$CMD" | clip
}

function force_export() {
    local var_name="$1"
    local new_value="$2"
    local temp_var="_${var_name}"

    eval "${temp_var}=\"${new_value}\""
    unset "$var_name"
    eval "export ${var_name}=\"\$${temp_var}\""
}

function print_info() {
    info "ARCH:     $ARCH"
    info "CC:       $CC"
    info "KSRC:     $KSRC"
    info "KOBJ:     $KOBJ"
    info "FS:       $FS"
    info "SSH_PORT: $SSH_PORT"
    info "GDB_PORT: $GDB_PORT"
    info "SHARE:    $SHARE"
}

function current_reset() {
    unset SCRIPTS PRJ FILEPATH_ENV
    unset DEF_ARCH DEF_CC DEF_SSH_PORT DEF_GDB_PORT IMAGES RANDOM
    unset ARCH SHARE TMP SYZKALLER PATCH
    unset KSRC KOBJ FS CC LLVM CROSS_COMPILE SSH_PORT GDB_PORT
    unset _READY
    info "All environment variables have been reset."
}

# ──────────────────────────────────────────────────────────────────────────────
# 3) KSRC override (SRC > KSRC)
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$SRC" ] && [ "$SRC" != "" ]; then
    # New SRC takes priority
    force_export "KSRC" "$PRJ/kernels/$SRC"
    unset SRC
else
    if [ -n "$KSRC" ] && [ "$KSRC" != "" ]; then
        # Keep existing KSRC
        force_export "KSRC" "$KSRC"
    else
        error "Error: SRC/KSRC not set"
        return 1
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4) KOBJ override (OBJ > KOBJ) - build dir under KSRC
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$OBJ" ] && [ "$OBJ" != "" ]; then
    # New OBJ takes priority
    force_export "KOBJ" "$KSRC/build/$OBJ"
    unset OBJ
else
    if [ -n "$KOBJ" ] && [ "$KOBJ" != "" ]; then
        # Keep existing KOBJ
        force_export "KOBJ" "$KOBJ"
    else
        error "Error: OBJ/KOBJ not set"
        return 1
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5) FS override (FS > default by ARCH)
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$FS" ] && [ "$FS" != "" ]; then
    force_export "FS" "$FS"
else
    # Default: determined by ARCH
    if [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ]; then
        force_export "FS" "$IMAGES/x64"
    elif [ "$ARCH" == "arm64" ]; then
        force_export "FS" "$IMAGES/arm64"
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6) SSH_PORT override
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "" ]; then
    force_export "SSH_PORT" "$SSH_PORT"
else
    force_export "SSH_PORT" "$DEF_SSH_PORT"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 7) GDB_PORT override
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$GDB_PORT" ] && [ "$GDB_PORT" != "" ]; then
    force_export "GDB_PORT" "$GDB_PORT"
else
    force_export "GDB_PORT" "$DEF_GDB_PORT"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 8) CC override (CC > default: llvm-19)
#    CC=llvm-19  → LLVM=-19 (full LLVM toolchain with version suffix)
#    CC=llvm     → LLVM=1   (full LLVM toolchain, no version suffix)
#    CC=gcc      → CROSS_COMPILE set by ARCH for cross-compilation
# ──────────────────────────────────────────────────────────────────────────────
if [ -z "$CC" ] || [ "$CC" == "" ]; then
    CC="$DEF_CC"
fi
force_export "CC" "$CC"

# Reset previous toolchain variables
unset LLVM CROSS_COMPILE

case "$CC" in
    llvm-*)
        # e.g. llvm-19 → LLVM=-19
        _llvm_suffix="${CC#llvm}"
        export LLVM="$_llvm_suffix"
        unset _llvm_suffix
        ;;
    llvm)
        export LLVM=1
        ;;
    gcc)
        if [ "$ARCH" == "arm64" ]; then
            export CROSS_COMPILE="aarch64-linux-gnu-"
        fi
        ;;
    *)
        error "Error: CC not supported: $CC (use llvm-19, llvm, or gcc)"
        return 1
        ;;
esac

# ──────────────────────────────────────────────────────────────────────────────
# 9) Final output and directory setup
# ──────────────────────────────────────────────────────────────────────────────

current

if [ ! -d "$KOBJ" ]; then
    mkdir -p "$KOBJ"
fi

if [ -d "$KOBJ/source" ]; then
    if [ "$(realpath "$KOBJ/source")" != "$(realpath "$KSRC")" ]; then
        error "Error: $KOBJ/source does not match with $KSRC"
        return 1
    fi
fi

export _READY=1
