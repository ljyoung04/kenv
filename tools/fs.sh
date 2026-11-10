#!/usr/bin/env bash
# Image management usable directly, without an interactive shell environment.
set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/.common.sh"

usage() {
    cat <<'EOF'
Usage: fs.sh <command>
  ls                         List bookworm images
  create <name> [-a arch] [-s MB] [-d distro]
                             Create an image in a NEW images/<name> directory
                             Defaults: x86_64, 5120 MB, bookworm
  help                       Show help

Creation requires sudo/debootstrap and mounts a disk image. VM profiles use
bookworm.img + bookworm.id_rsa; other distributions are for standalone use.
EOF
}

cmd_ls() {
    if [ "$#" -ne 0 ]; then error "Usage: fs.sh ls"; return 2; fi
    local dir size arch found=0 in_use
    for dir in "$IMAGES"/*/; do
        [ -f "$dir/bookworm.img" ] || continue
        found=1
        size=$(du --apparent-size -h "$dir/bookworm.img" | cut -f1)
        arch="?"
        [ ! -f "$dir/.arch" ] || arch=$(cat "$dir/.arch")
        in_use=""
        if fuser "$dir/bookworm.img" >/dev/null 2>&1; then in_use=" [IN USE]"; fi
        printf '[%s] bookworm.img (%s, %s)%s\n' "$(basename "$dir")" "$size" "$arch" "$in_use"
    done
    if [ "$found" -eq 0 ]; then info "No bookworm.img found under $IMAGES"; fi
}

cmd_create() {
    case "${1:-}" in ""|-h|--help) usage; return 0 ;; esac
    local name="$1" arch=x86_64 size=5120 distro=bookworm
    shift
    validate_scope_name "Image name" "$name" || return 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -a|--arch|-s|--size|-d|--distro)
                if [ "$#" -lt 2 ]; then error "$1 requires a value"; return 2; fi
                case "$1" in
                    -a|--arch) arch="$2" ;;
                    -s|--size) size="$2" ;;
                    -d|--distro) distro="$2" ;;
                esac
                shift 2 ;;
            -h|--help) usage; return 0 ;;
            *) error "Unknown option: $1"; return 2 ;;
        esac
    done
    validate_scope_name "Distribution" "$distro" || return 2
    validate_scope_name "Architecture" "$arch" || return 2
    if [[ ! "$size" =~ ^[1-9][0-9]*$ ]]; then
        error "Image size must be a positive integer in MB"; return 2
    fi
    case "$arch" in arm64) arch=aarch64 ;; amd64) arch=x86_64 ;; esac
    local dir="$IMAGES/$name"
    mkdir -p "$IMAGES"
    if ! mkdir "$dir"; then
        error "Refusing to reuse image directory: $dir"; return 1
    fi
    printf '%s\n' "$arch" > "$dir/.arch"
    info "Creating images/$name/$distro.img ($arch, ${size}MB)"
    if ! (cd "$dir" && "$SCRIPTS/create-image.sh" -a "$arch" -d "$distro" -s "$size"); then
        error "Image creation failed; partial files preserved in $dir"
        return 1
    fi
    if [ ! -f "$dir/$distro.img" ]; then
        error "Image file not created: $dir/$distro.img"; return 1
    fi
    # create-image.sh elevates individual operations, keeping output keys/images
    # owned by the caller. Only the temporary root filesystem needs cleanup.
    if [ -d "$dir/$distro" ]; then
        sudo rm -rf -- "$dir/$distro"
    fi
    info "Created: $dir/$distro.img"
}

cmd="${1:-help}"
if [ "$#" -gt 0 ]; then shift; fi
case "$cmd" in
    ls) cmd_ls "$@" ;;
    create) cmd_create "$@" ;;
    help|-h|--help) usage ;;
    *) error "Unknown command: $cmd"; usage; exit 2 ;;
esac
