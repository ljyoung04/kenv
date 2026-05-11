#!/usr/bin/env bash
# linux-env: kernel build / config helpers. Stateless CLI — profile is always
# passed explicitly via -p. Inherited profile-scope env from the parent shell
# is ignored.
#
# Humans typically use the `kernel` shell function defined in env.sh, which
# auto-injects -p from $PROFILE. Agents pass it explicitly:
#   kernel.sh -p <profile> --build [-j N]

set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.common.sh"

# Start clean. -p will repopulate profile-scope vars.
unset PROFILE PROFILE_SH ARCH LLVM FS KSRC KOBJ KIMAGE

usage() {
    cat <<'EOF'
Usage: kernel.sh -p <profile> <command>

  --help                 Show this help (no -p needed)
  --menuconfig           make -C $KSRC O=$KOBJ menuconfig (ARCH/LLVM injected)
  --olddefconfig         make -C $KSRC O=$KOBJ olddefconfig
  --kctfconfig           cp $CONFIGS/kernelctf.config $KOBJ/.config
  --build [-j N]         make -C $KSRC O=$KOBJ -jN (default 16)
  --clang                Generate compile_commands.json + drop $KSRC/.clangd

-p <profile> is STRICTLY required for all commands except --help (no inherited
env). --build / --menuconfig / --olddefconfig / --clang require Variant A
profiles (KSRC + KOBJ).
EOF
}

require_profile() {
    : "${PRJ:?PRJ not set; source scripts/env.sh first}"
    if [ -z "${PROFILE:-}" ]; then
        error "this subcommand requires -p <profile>"
        exit 2
    fi
}

require_build_ctx() {
    require_profile
    : "${ARCH:?ARCH not set in profile}"
    : "${LLVM:?LLVM not set in profile}"
    : "${KSRC:?KSRC not set; profile is Variant B (KIMAGE) which has no source tree}"
    : "${KOBJ:?KOBJ not set; profile is Variant B (KIMAGE) which has no build dir}"
    if [ ! -d "$KSRC" ]; then
        error "KSRC directory missing: $KSRC"
        exit 1
    fi
    mkdir -p "$KOBJ"
}

# Build the make-arg array: ARCH/LLVM/CROSS_COMPILE injection.
build_make_args() {
    local args=()
    args+=("-C" "$KSRC" "O=$KOBJ" "ARCH=$ARCH")
    case "${LLVM:-}" in
        ""|"0")
            # gcc toolchain. arm64 needs CROSS_COMPILE.
            if [ "$ARCH" = "arm64" ] && [ -z "${CROSS_COMPILE:-}" ]; then
                args+=("CROSS_COMPILE=aarch64-linux-gnu-")
            fi
            ;;
        "1")
            args+=("LLVM=1")
            ;;
        *)
            # e.g. -19 or 19 → LLVM=-19
            local v="$LLVM"
            case "$v" in
                -*) ;;     # already has dash
                *)  v="-$v" ;;
            esac
            args+=("LLVM=$v")
            ;;
    esac
    printf '%s\n' "${args[@]}"
}

cmd_menuconfig() {
    require_build_ctx
    local margs=()
    while IFS= read -r line; do margs+=("$line"); done < <(build_make_args)
    info "make ${margs[*]} menuconfig"
    exec make "${margs[@]}" menuconfig
}

cmd_olddefconfig() {
    require_build_ctx
    local margs=()
    while IFS= read -r line; do margs+=("$line"); done < <(build_make_args)
    info "make ${margs[*]} olddefconfig"
    exec make "${margs[@]}" olddefconfig
}

cmd_kctfconfig() {
    require_profile
    : "${KOBJ:?KOBJ not set; profile is Variant B (KIMAGE) which has no build dir}"
    : "${CONFIGS:?CONFIGS not set; source env.sh first}"
    local src="$CONFIGS/kernelctf.config"
    if [ ! -f "$src" ]; then
        error "kernelctf.config not found at $src"
        exit 1
    fi
    mkdir -p "$KOBJ"
    cp "$src" "$KOBJ/.config"
    info "Copied $src → $KOBJ/.config"
    info "Next: kernel.sh --olddefconfig"
}

cmd_build() {
    require_build_ctx
    local jobs=16
    while [ $# -gt 0 ]; do
        case "$1" in
            -j) jobs="${2:?-j requires N}"; shift 2 ;;
            -j*) jobs="${1#-j}"; shift ;;
            *) error "Unknown option: $1"; exit 2 ;;
        esac
    done
    local margs=()
    while IFS= read -r line; do margs+=("$line"); done < <(build_make_args)
    info "make ${margs[*]} -j$jobs"
    exec make "${margs[@]}" "-j$jobs"
}

cmd_clang() {
    require_build_ctx
    local gen="$KSRC/scripts/clang-tools/gen_compile_commands.py"
    if [ ! -f "$gen" ]; then
        error "gen_compile_commands.py not found: $gen"
        exit 1
    fi
    info "Running gen_compile_commands.py..."
    "$gen" -d "$KOBJ" -o "$KSRC/compile_commands.json"
    info "Wrote $KSRC/compile_commands.json"
    if [ ! -f "$KSRC/.clangd" ]; then
        local src="$CONFIGS/.clangd"
        if [ -f "$src" ]; then
            cp "$src" "$KSRC/.clangd"
            info "Copied $src → $KSRC/.clangd"
        else
            warn ".clangd template not found at $src; skipping"
        fi
    else
        info "$KSRC/.clangd already exists; not overwriting"
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

# Parse top-level -p flag (must come before the subcommand).
PROFILE_ARG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--profile)
            if [ "$#" -lt 2 ]; then error "-p requires <profile>"; exit 2; fi
            PROFILE_ARG="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

: "${PRJ:?PRJ not set; source scripts/env.sh first}"

if [ -n "$PROFILE_ARG" ]; then
    PROFILE="$PRJ/profiles/$PROFILE_ARG"
    PROFILE_SH="$PROFILE/profile.sh"
    if [ ! -f "$PROFILE_SH" ]; then
        error "profile.sh missing: $PROFILE_SH"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$PROFILE_SH"
    export PROFILE PROFILE_SH
fi

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

cmd="$1"; shift
case "$cmd" in
    -h|--help)         usage ;;
    --menuconfig)      cmd_menuconfig   "$@" ;;
    --olddefconfig)    cmd_olddefconfig "$@" ;;
    --kctfconfig)      cmd_kctfconfig   "$@" ;;
    --build)           cmd_build        "$@" ;;
    --clang)           cmd_clang        "$@" ;;
    *) error "Unknown command: $cmd"; usage; exit 2 ;;
esac
