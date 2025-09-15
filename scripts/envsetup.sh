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

export SCRIPT_DIR="$(realpath "$(dirname "$_SCRIPT_SOURCE")")"
export PRJ="$(dirname "$SCRIPT_DIR")"
export SSH_PORT=20202

unset _READY
source "$SCRIPT_DIR/.common.sh"

export DEF_KVER="6.6"
export DEF_ARCH="arm64"

# ──────────────────────────────────────────────────────────────────────────────
# 1) ARCH 설정 (기존 로직 그대로)
# ──────────────────────────────────────────────────────────────────────────────
if [ -z "$ARCH" ] || [ "$ARCH" == "" ]; then
    ARCH="$DEF_ARCH"
fi

_ARCH="$ARCH"
unset ARCH
export ARCH="$_ARCH"

if [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ]; then
    export IMAGE="$PRJ/images/x64"
elif [ "$ARCH" == "arm64" ]; then
    export IMAGE="$PRJ/images/arm64"
else
    error "Error: ARCH not supported: $ARCH"
    return 1
fi

export SHARE="$PRJ/share"
export SYZKALLER="$PRJ/syzkaller"
export PATCH="$PRJ/patch"

# commands

function current() {
    CMD="ARCH=$ARCH KVER=$KVER KSRC=$KSRC KOBJ=$KOBJ source $SCRIPT_DIR/envsetup.sh"
    info "ARCH: $ARCH"
    info "KVER: $KVER"
    info "KSRC: $KSRC"
    info "KOBJ: $KOBJ"
    info "$CMD"
    info "Try to copy to clipboard..."
    echo "$CMD" | clip
}

function force_export() {
    local var_name="$1"      # 첫 번째 인자: 환경변수 이름
    local new_value="$2"     # 두 번째 인자: 새로운 값
    local temp_var="_${var_name}"  # 임시 변수명 생성
    
    # 1. 현재 값을 임시 변수에 저장
    eval "${temp_var}=\"${new_value}\""
    # 2. 원본 변수 제거
    unset "$var_name"
    # 3. 새 값으로 export
    eval "export ${var_name}=\"\$${temp_var}\""
}

function print_info() {    
    info "ARCH: $ARCH"
    info "KVER: $KVER"
    info "KSRC: $KSRC"
    info "KOBJ: $KOBJ"
    info "IMAGE: $IMAGE"
    info "SHARE: $SHARE"
}


# ──────────────────────────────────────────────────────────────────────────────
# 2) KVER 설정 (기존 로직 그대로)
# ──────────────────────────────────────────────────────────────────────────────
if [ -z "$KVER" ] || [ "$KVER" == "" ]; then
    KVER="$DEF_KVER"
fi

force_export "KVER" "$KVER"

# ──────────────────────────────────────────────────────────────────────────────
# 3) KSRC Override 로직 (Priority: 새로 넘어온 SRC > 기존 KSRC)
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$SRC" ] && [ "$SRC" != "" ]; then
    # 3-1) 사용자가 새로 SRC=값 을 준 경우 → 무조건 이쪽이 우선
    force_export "KSRC" "$PRJ/kernels/$SRC"
    unset SRC
else
    # 3-2) 사용자가 SRC 를 주지 않았다면, 외부에서 이미 KSRC 환경변수로 설정된 게 있는지 확인
    if [ -n "$KSRC" ] && [ "$KSRC" != "" ]; then
        # 외부 KSRC 가 있으면 그대로 사용
        force_export "KSRC" "$KSRC"
    else
        # SRC 도 없고, 외부 KSRC 도 없으면 에러
        error "Error: SRC/KSRC not set"
        return 1
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4) KOBJ Override 로직 - KSRC 하위 build 디렉토리로 변경
# ──────────────────────────────────────────────────────────────────────────────
if [ -n "$OBJ" ] && [ "$OBJ" != "" ]; then
    # 4-1) 사용자가 새로 OBJ=값 을 준 경우 → KSRC/build/OBJ 로 설정
    force_export "KOBJ" "$KSRC/build/$OBJ"
    unset OBJ
else
    # 4-2) 사용자가 OBJ 주지 않았다면, 외부에서 이미 KOBJ 환경변수로 설정된 게 있는지 확인
    if [ -n "$KOBJ" ] && [ "$KOBJ" != "" ]; then
        # 외부 KOBJ 가 있으면 그대로 사용
        force_export "KOBJ" "$KOBJ"
    else
        # OBJ 도 없고, 외부 KOBJ 도 없으면 에러
        error "Error: OBJ/KOBJ not set"
        return 1
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5) 최종 상태 출력 및 디렉토리 생성 (기존 로직 그대로)
# ──────────────────────────────────────────────────────────────────────────────

print_info

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
