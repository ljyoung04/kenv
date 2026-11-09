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
export IMAGES="$PRJ/images"
export CONFIGS="$PRJ/configs"
export LOGS="$PRJ/logs"
mkdir -p "$LOGS" 2>/dev/null || true

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
    local CMD="ARCH=$ARCH CC=$CC KSRC=$KSRC KOBJ=$KOBJ FS=$FS"
    if [ -n "${SSH_PORT:-}" ]; then
        CMD="SSH_PORT=$SSH_PORT $CMD"
    fi
    CMD="$CMD source $SCRIPTS/envsetup.sh"
    case "$1" in
        -x)
            echo $CMD | clip
            info "Environment command copied to clipboard."
            ;;
        -s)
            print_info
            info "$CMD"
            echo "current -c 2>/dev/null" >| "$FILEPATH_ENV"
            echo "$CMD" >> "$FILEPATH_ENV"
            warn "Run 'source ~/$(basename "$FILEPATH_ENV")' to restore this environment"
            ;;
        -r)
            unset KSRC KOBJ FS CC LLVM CROSS_COMPILE SSH_PORT GDB_PORT
            unset _READY
            info "Kernel environment reset. Common variables (PRJ, SCRIPTS, IMAGES, ...) preserved."
            ;;
        -c)
            unset SCRIPTS PRJ FILEPATH_ENV
            unset DEF_ARCH DEF_CC DEF_SSH_PORT IMAGES CONFIGS
            unset ARCH SHARE RANDOMS SYZKALLER PATCHES
            unset KSRC KOBJ FS CC LLVM CROSS_COMPILE SSH_PORT GDB_PORT
            unset _READY
            info "All environment variables have been reset."
            ;;
        *)
            print_info
            info "$CMD"
            ;;
    esac
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
    if [ -n "$FS" ] && [ "$FS" != "" ]; then
        info "FS:       $FS"
    else
        warn "FS:       (not set) Use 'lsfs' / 'setfs <name>' / 'mkfs <name>'"
    fi
    if [ -n "${SSH_PORT:-}" ]; then
        info "SSH_PORT: $SSH_PORT"
        info "GDB_PORT: ${GDB_PORT:-$((SSH_PORT - 20000))}"
    else
        info "SSH_PORT: (unset; auto-allocated by run-vm.sh)"
    fi
    info "SHARE:    $SHARE"
    info "LOGS:     $LOGS"
}

function lsfs() {
    local img_dir="$IMAGES"
    if [ ! -d "$img_dir" ]; then
        error "Images directory not found: $img_dir"
        return 1
    fi

    local found=0
    local current_name=""
    if [ -n "$FS" ] && [ "$FS" != "" ]; then
        current_name="$(basename "$FS")"
    fi

    for dir in "$img_dir"/*/; do
        [ -d "$dir" ] || continue
        local name="$(basename "$dir")"
        local img="$dir/bookworm.img"
        if [ -f "$img" ]; then
            found=1
            local size
            size=$(du --apparent-size -h "$img" 2>/dev/null | cut -f1)
            local marker="  "
            if [ "$name" = "$current_name" ]; then
                marker="* "
            fi
            local status=""
            if fuser "$img" >/dev/null 2>&1; then
                status=" [IN USE]"
            fi
            local arch="?"
            if [ -f "$dir/.arch" ]; then
                arch=$(cat "$dir/.arch")
            fi
            printf "%s[%s] bookworm.img (%s, %s)%s\n" "$marker" "$name" "$size" "$arch" "$status"
        fi
    done

    if [ "$found" -eq 0 ]; then
        warn "No bookworm.img found under $img_dir"
    fi

    if [ -z "$current_name" ]; then
        echo ""
        warn "FS not set"
    fi
}

function setfs() {
    if [ -z "$1" ]; then
        error "Usage: setfs <name>"
        error "  e.g. setfs x64"
        return 1
    fi

    local target="$IMAGES/$1"
    if [ ! -d "$target" ]; then
        error "Directory not found: $target"
        lsfs
        return 1
    fi

    force_export "FS" "$target"
    info "FS: $FS"
}

function mkfs() {
    local name=""
    local arch="$ARCH"
    local size=5120
    local distro="bookworm"

    # Help / no-args
    if [ $# -eq 0 ] || [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: mkfs <name> [-a arch] [-s size_MB] [-d distro]"
        echo ""
        echo "  <name>       Image directory name (required)"
        echo "  -a, --arch   Architecture (default: \$ARCH=$ARCH)"
        echo "  -s, --size   Image size in MB (default: 5120)"
        echo "  -d, --distro Debian distribution (default: bookworm)"
        echo ""
        echo "Examples:"
        echo "  mkfs myimg"
        echo "  mkfs myimg -a arm64 -s 10240"
        echo "  mkfs myimg -d bookworm -s 2048"
        return 0
    fi

    # First arg must be the name (not an option)
    if [[ "$1" == -* ]]; then
        error "Usage: mkfs <name> [-a arch] [-s size_MB] [-d distro]"
        return 1
    fi

    name="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch)   arch="$2"; shift 2 ;;
            -s|--size)   size="$2"; shift 2 ;;
            -d|--distro) distro="$2"; shift 2 ;;
            -h|--help)
                mkfs --help
                return 0
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local img_dir="$IMAGES/$name"
    local img_file="$img_dir/$distro.img"

    # Check if image already exists
    if [ -f "$img_file" ]; then
        error "Image already exists: $img_file"
        return 1
    fi

    # Convert ARCH to create-image.sh expected format
    local ci_arch="$arch"
    case "$arch" in
        arm64)  ci_arch="aarch64" ;;
        amd64)  ci_arch="x86_64" ;;
    esac

    info "Creating filesystem image: images/$name/"
    info "Arch: $ci_arch, Distro: $distro, Size: ${size}MB"

    # Create directory and save arch metadata
    mkdir -p "$img_dir"
    echo "$ci_arch" > "$img_dir/.arch"

    # Run create-image.sh from the image directory
    local prev_dir="$PWD"
    cd "$img_dir"
    if ! sudo "$SCRIPTS/create-image.sh" -a "$ci_arch" -d "$distro" -s "$size"; then
        cd "$prev_dir"
        error "create-image.sh failed"
        return 1
    fi
    cd "$prev_dir"

    # Fix ownership (create-image.sh runs as root)
    sudo chown "$(id -u):$(id -g)" "$img_dir"/*

    # Clean up debootstrap directory
    if [ -d "$img_dir/$distro" ]; then
        info "Cleaning up debootstrap directory..."
        sudo rm -rf "$img_dir/$distro"
    fi

    # Verify result
    if [ ! -f "$img_file" ]; then
        error "Image file not created: $img_file"
        return 1
    fi

    local img_size
    img_size=$(du -h "$img_file" 2>/dev/null | cut -f1)
    info "Created: images/$name/$distro.img ($img_size)"

    # Auto-select the new image
    setfs "$name"
}

function vmhttp() {
    local dir="${1:-${SHARE:-.}}"
    local port="${2:-8888}"

    if [ ! -d "$dir" ]; then
        error "Directory not found: $dir"
        return 1
    fi

    dir="$(realpath "$dir")"
    info "Serving $dir on port $port"
    info "curl -O 10.0.2.2:$port/<filename>"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir"
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
# 5) FS override (optional - kernel build doesn't require FS)
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$FS" ] && [ "$FS" != "" ]; then
    force_export "FS" "$FS"
else
    force_export "FS" ""
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6) SSH_PORT / GDB_PORT
#    Allocation moved to run-vm.sh. envsetup.sh only preserves an existing
#    SSH_PORT/GDB_PORT in the environment if the caller set one explicitly.
# ──────────────────────────────────────────────────────────────────────────────

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

export -n CC   # keep CC as shell variable only, not exported to child processes

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
