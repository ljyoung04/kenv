#!/usr/bin/env bash
# Launch a kernel VM under QEMU.
#
# Default mode: background, in tmux session 'vm', new window named after the
# allocated SSH_PORT. Foreground mode (-f) keeps legacy stdio behavior.
#
# Port allocation: when SSH_PORT is unset, picks a free pair (SSH, SSH-20000)
# from 25000-29999. Setting SSH_PORT explicitly skips allocation.

set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/.common.sh"

# --- Defaults ---
DIRECT_KERNEL=""
ENABLE_FSDEV=false
ENABLE_PAGE_TABLE_CHECK=false
ENABLE_STOP=false
ENABLE_KASLR=false
FOREGROUND=false

usage() {
    cat <<'EOF'
Usage: run-vm.sh [options]

Options:
  -f, --foreground       Run in current terminal (legacy mode, no tmux)
  --kernel <bzImage>     Use a specific kernel image instead of $KOBJ/...
  -k                     Enable KASLR (default: nokaslr)
  -S                     Stop CPU at boot (for gdb attach)
  -s, --shared           Enable 9p host_share fsdev
  -p, --page-check       Enable page_table_check
  -h, --help             Show this help

Default: background. The VM runs inside a tmux window in session 'vm';
attach with `tmux attach -t vm:<SSH_PORT>` or `vm.sh --attach <SSH_PORT>`.

SSH_PORT is always auto-allocated (existing $SSH_PORT in the env is ignored).
GDB_PORT is always SSH_PORT-20000.
EOF
}

# --- Parse flags ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)        usage; exit 0 ;;
        --kernel)         DIRECT_KERNEL="$2"; shift 2 ;;
        -f|--foreground)  FOREGROUND=true;  shift ;;
        -k)               ENABLE_KASLR=true; shift ;;
        -S)               ENABLE_STOP=true;  shift ;;
        -s|--shared)      ENABLE_FSDEV=true; shift ;;
        -p|--page-check)  ENABLE_PAGE_TABLE_CHECK=true; shift ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# --- Required env validation ---
: "${PRJ:?'PRJ not set; run: source scripts/envsetup.sh'}"
: "${LOGS:?'LOGS not set; run: source scripts/envsetup.sh'}"
: "${SHARE:?'SHARE not set; run: source scripts/envsetup.sh'}"
mkdir -p "$LOGS" "$SHARE"

# --- Kernel image resolution ---
if [ -n "$DIRECT_KERNEL" ]; then
    if [ ! -f "$DIRECT_KERNEL" ]; then
        error "Kernel not found: $DIRECT_KERNEL"
        exit 1
    fi
    KERNEL_IMAGE="$(realpath "$DIRECT_KERNEL")"
else
    if [ -z "${KOBJ:-}" ]; then
        error "KOBJ not set; build a kernel or use --kernel <bzImage>"
        exit 1
    fi
    KERNEL_IMAGE="$KOBJ/arch/x86/boot/bzImage"
    if [ ! -f "$KERNEL_IMAGE" ]; then
        error "Kernel not found: $KERNEL_IMAGE (build first or use --kernel)"
        exit 1
    fi
fi

# --- FS validation ---
if [ -z "${FS:-}" ]; then
    error "FS not set. Use 'setfs <name>' (run 'lsfs' to list)."
    exit 1
fi
if [ ! -f "$FS/bookworm.img" ]; then
    error "Image not found: $FS/bookworm.img"
    exit 1
fi
if fuser "$FS/bookworm.img" >/dev/null 2>&1; then
    warn "$FS/bookworm.img is in use by another process."
    warn "Running multiple QEMU instances on the same image may cause corruption."
    if [ "$FOREGROUND" = "true" ]; then
        read -p "Continue anyway? [y/N] " -r
        if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# --- Port allocation ---
allocate_port_pair() {
    local p
    for _ in $(seq 1 200); do
        p=$(shuf -i 25000-29999 -n 1)
        if check_port_available "$p" && check_port_available "$((p - 20000))"; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# Always auto-allocate; an existing SSH_PORT in the environment is ignored so
# `vm.sh --list` and tmux window names are unique per VM.
unset SSH_PORT
if ! SSH_PORT=$(allocate_port_pair); then
    error "Could not find a free SSH/GDB port pair in 25000-29999"
    exit 1
fi
GDB_PORT=$(( SSH_PORT - 20000 ))
if [ "$GDB_PORT" -le 0 ]; then
    error "SSH_PORT $SSH_PORT too small (GDB_PORT would be $GDB_PORT, must be > 0)"
    exit 1
fi

LOG_FILE="$LOGS/vm-$SSH_PORT.log"
META_FILE="$LOGS/vm-$SSH_PORT.json"
PID_FILE="$LOGS/vm-$SSH_PORT.pid"
MON_FILE="$LOGS/vm-$SSH_PORT.mon"

# Pre-check that the metadata file isn't claimed by an already-running VM.
if [ -f "$META_FILE" ]; then
    EXISTING_PID="$(grep -oE '"pid": *[0-9]+' "$META_FILE" | head -1 | grep -oE '[0-9]+' || true)"
    if [ -n "$EXISTING_PID" ] && [ "$EXISTING_PID" -gt 0 ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        error "VM already running on SSH_PORT=$SSH_PORT (pid=$EXISTING_PID). Use 'vm.sh --kill $SSH_PORT' first."
        exit 1
    fi
    rm -f "$META_FILE"
fi
rm -f "$PID_FILE" "$MON_FILE"

# --- Build QEMU command ---
QEMU_BIN=qemu-system-x86_64

KERNEL_APPEND="console=ttyS0 root=/dev/vda earlyprintk=serial net.ifnames=0 page_poison=1 kasan_multi_shot panic=0"
KERNEL_APPEND="$KERNEL_APPEND no_hash_pointers acpi=noirq oops=oops"
if [ "$ENABLE_KASLR" = "false" ]; then
    KERNEL_APPEND="$KERNEL_APPEND nokaslr"
fi
if [ "$ENABLE_PAGE_TABLE_CHECK" = "true" ]; then
    KERNEL_APPEND="$KERNEL_APPEND page_table_check=on"
fi

QEMU_ARGS=(
    -m 3.5G
    -cpu host
    -smp 2
    -kernel "$KERNEL_IMAGE"
    -append "$KERNEL_APPEND"
    -drive "file=$FS/bookworm.img,format=raw,snapshot=on,if=virtio"
    -nic "user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22"
    -chardev "stdio,id=char0,mux=on,signal=off,logfile=$LOG_FILE,logappend=off"
    -serial "chardev:char0"
    -enable-kvm
    -nographic
    -pidfile "$PID_FILE"
    -monitor "unix:$MON_FILE,server,nowait"
    -gdb "tcp::${GDB_PORT}"
)
if [ "$ENABLE_FSDEV" = "true" ]; then
    QEMU_ARGS+=(
        -fsdev "local,security_model=passthrough,id=fsdev0,path=$SHARE/"
        -device "virtio-9p-pci,fsdev=fsdev0,mount_tag=host_share"
    )
fi
if [ "$ENABLE_STOP" = "true" ]; then
    QEMU_ARGS+=(-S)
fi

print_banner() {
    cat <<EOF
=================================================
 KERNEL:   $KERNEL_IMAGE
 KSRC:     ${KSRC:-<none>}
 KOBJ:     ${KOBJ:-<none>}
 FS:       $FS
 SHARE:    $SHARE
 SSH_PORT: $SSH_PORT
 GDB_PORT: $GDB_PORT
 LOG:      $LOG_FILE
=================================================
EOF
}

# --- Foreground mode (legacy) ---
if [ "$FOREGROUND" = "true" ]; then
    print_banner
    exec "$QEMU_BIN" "${QEMU_ARGS[@]}"
fi

# --- Background mode (tmux) ---
if ! command -v tmux >/dev/null 2>&1; then
    error "tmux not found; use -f for foreground mode"
    exit 1
fi

if ! tmux has-session -t vm 2>/dev/null; then
    tmux new-session -d -s vm -n "shell" "bash"
fi

if tmux list-windows -t vm -F '#{window_name}' 2>/dev/null | grep -qx "$SSH_PORT"; then
    error "tmux window vm:$SSH_PORT already exists"
    exit 1
fi

# Build a single shell-quoted command for the tmux pane.
QEMU_CMD="$QEMU_BIN"
for a in "${QEMU_ARGS[@]}"; do
    QEMU_CMD+=" $(printf '%q' "$a")"
done

# Trail with `read` so the window stays open after qemu exits (so users can read errors).
WINDOW_CMD="$QEMU_CMD; ec=\$?; echo; echo '[VM exited (status='\$ec'); press Enter to close]'; read -r _"

# Determine vmlinux path for the metadata.
VMLINUX_PATH=""
if [ -n "${KOBJ:-}" ] && [ -f "$KOBJ/vmlinux" ]; then
    VMLINUX_PATH="$KOBJ/vmlinux"
fi

# Write metadata BEFORE launching, with pid=0; we'll update pid once QEMU writes
# its pidfile. Doing it early guarantees vm.sh --list shows the VM even if the
# pidfile read races or fails.
write_metadata() {
    local pid="$1"
    {
        printf '{\n'
        printf '  "ssh_port": %s,\n' "$SSH_PORT"
        printf '  "gdb_port": %s,\n' "$GDB_PORT"
        printf '  "kernel_image": "%s",\n' "$KERNEL_IMAGE"
        printf '  "ksrc": "%s",\n' "${KSRC:-}"
        printf '  "kobj": "%s",\n' "${KOBJ:-}"
        printf '  "vmlinux": "%s",\n' "$VMLINUX_PATH"
        printf '  "fs": "%s",\n' "$FS"
        printf '  "pid": %s,\n' "$pid"
        printf '  "tmux_window": "vm:%s",\n' "$SSH_PORT"
        printf '  "log": "%s",\n' "$LOG_FILE"
        printf '  "started_at": "%s"\n' "$(date -Iseconds)"
        printf '}\n'
    } > "$META_FILE"
}

write_metadata 0

tmux new-window -t vm: -n "$SSH_PORT" -d "$WINDOW_CMD"

# Wait for QEMU to write its pidfile (or exit).
QEMU_PID=0
for _ in $(seq 1 40); do
    if [ -f "$PID_FILE" ] && [ -s "$PID_FILE" ]; then
        QEMU_PID="$(cat "$PID_FILE" 2>/dev/null || echo 0)"
        if [[ "$QEMU_PID" =~ ^[0-9]+$ ]] && [ "$QEMU_PID" -gt 0 ]; then
            break
        fi
        QEMU_PID=0
    fi
    if ! tmux list-windows -t vm -F '#{window_name}' 2>/dev/null | grep -qx "$SSH_PORT"; then
        error "tmux window vm:$SSH_PORT vanished before QEMU started; check $LOG_FILE"
        rm -f "$META_FILE"
        exit 1
    fi
    sleep 0.25
done
if [ "$QEMU_PID" -eq 0 ]; then
    warn "QEMU did not write a readable pidfile within 10s; recording pid=0"
    warn "Inspect: tmux attach -t vm:$SSH_PORT  /  tail $LOG_FILE"
fi

# Update metadata with the actual pid.
write_metadata "$QEMU_PID"

# Background-mode stdout is shaped so `eval $(run-vm.sh)` sets SSH_PORT/GDB_PORT
# in the parent shell. The banner is comment-prefixed; only the export line is
# live shell code.
sed 's/^/# /' <<EOF
=================================================
 KERNEL:   $KERNEL_IMAGE
 KSRC:     ${KSRC:-<none>}
 KOBJ:     ${KOBJ:-<none>}
 FS:       $FS
 SHARE:    $SHARE
 SSH_PORT: $SSH_PORT
 GDB_PORT: $GDB_PORT
 LOG:      $LOG_FILE
 TMUX:     vm:$SSH_PORT  (attach: tmux attach -t vm:$SSH_PORT  /  vm.sh -a $SSH_PORT)
=================================================
EOF
echo "export SSH_PORT=$SSH_PORT GDB_PORT=$GDB_PORT"
