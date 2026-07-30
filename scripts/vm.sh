#!/usr/bin/env bash
# linux-env: vm management. Stateless CLI - profile/vm scope is always passed
# explicitly via -p/-v flags. Inherited env from the parent shell is ignored;
# `vm.sh` always starts with a clean profile/vm scope (PRJ stays since it's
# the project root).
#
# Humans typically don't call vm.sh directly; the `vm` shell function in
# env.sh auto-injects -p/-v from $PROFILE/$VM. Agents (and scripts) pass
# them explicitly: `vm.sh -p <profile> -v <vm> ssh -- ls`.

set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.common.sh"

# Start with a clean profile/vm scope. Subsequent -p/-v parsing fills them.
# Keep PRJ from the environment (the project root must be set by env.sh).
unset PROFILE PROFILE_SH ARCH LLVM FS KSRC KOBJ KIMAGE
unset VM VM_SH SSH_PORT GDB_PORT
unset VM_STARTED_AT VM_KERNEL_IMAGE VM_VMLINUX VM_KSRC VM_KOBJ VM_FS VM_LOG

usage() {
    cat <<'EOF'
Usage: vm.sh [-p <profile>] [-v <vm>] <command> [args]

The -p/-v flags are STRICTLY required (no inherited env). Profile-scope env
vars (ARCH/LLVM/FS/KSRC/KOBJ/KIMAGE) are loaded from $PRJ/profiles/<p>/profile.sh;
VM-scope (SSH_PORT/GDB_PORT/...) is loaded from .../vms/<v>/vm.sh.

Context-independent (no flags):
  ls [--json]              List registered profiles + static info
  ps [--json]              List running VMs (PID alive in /proc)
  help                     Show this help

Profile required (-p):
  run <vm_name> [opts]     Boot a new VM under -p. opts:
                             --shared   enable 9p host_share
                             --kaslr    enable KASLR (default: nokaslr)
                             --android  device-matched env (Pixel 10 6.6.82):
                                        8 cpu, 12G, rcu_nocbs=all + expedited

Profile + vm required (-p -v):
  ssh [-- <cmd>...]        SSH into the VM (no args → interactive shell). The
                           '--' before <cmd> is required when a remote command
                           is supplied. ConnectTimeout=1; on failure diagnoses
                           via boot.log (exit 251=unreachable, 252=panic).
  scp <src> <dst>          SCP between host and VM ('vm:/path' for remote side)
  gdb                      Attach gdb (auto-loads vmlinux when available)
  attach                   Attach to the VM's tmux window
  kill                     Stop QEMU process; preserve VM directory
  rm                       Remove the VM directory (target = -v; rejects live VM)
  log                      tail -f $VM/boot.log

State files (under $PRJ/profiles/<p>/vms/<v>/):
  vm.sh    SSH_PORT/GDB_PORT/metadata exports (sourced after -v)
  vm.pid   QEMU PID (single source of truth for liveness)
  boot.log serial console
EOF
}

# ---------------------------------------------------------------------------
# Liveness + meta helpers
# ---------------------------------------------------------------------------

is_pid_alive() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [ "$pid" -gt 0 ] || return 1
    [ -d "/proc/$pid" ]
}

read_pid() {
    local vdir="$1"
    if [ -f "$vdir/vm.pid" ]; then
        cat "$vdir/vm.pid" 2>/dev/null || true
    fi
}

# Replace a leading $PRJ path prefix with the literal string '$PRJ' for
# readability in tabular output. Empty input passes through unchanged.
prettify_path() {
    local p="${1:-}"
    if [ -n "${PRJ:-}" ] && [ -n "$p" ]; then
        case "$p" in
            "$PRJ")    printf '$PRJ\n'; return ;;
            "$PRJ"/*)  printf '$PRJ/%s\n' "${p#"$PRJ"/}"; return ;;
        esac
    fi
    printf '%s\n' "$p"
}

# Read a single 'export VAR=...' line from a vm.sh metadata file.
vm_meta_get() {
    local file="$1" key="$2"
    [ -f "$file" ] || { echo ""; return 0; }
    grep -E "^export[[:space:]]+${key}=" "$file" 2>/dev/null \
        | head -1 \
        | sed -E "s/^export[[:space:]]+${key}=//; s/^['\"]//; s/['\"]$//"
}

require_prj() {
    : "${PRJ:?PRJ not set; source scripts/env.sh first}"
}

require_profile() {
    require_prj
    if [ -z "${PROFILE:-}" ]; then
        error "this subcommand requires -p <profile>"
        exit 2
    fi
}

require_vm() {
    require_profile
    if [ -z "${VM:-}" ] || [ -z "${VM_SH:-}" ]; then
        error "this subcommand requires -p <profile> -v <vm>"
        exit 2
    fi
}

# ---------------------------------------------------------------------------
# tmux helpers
# ---------------------------------------------------------------------------

tmux_session_for_profile() {
    local pname="${1:-$(basename "$PROFILE")}"
    # tmux disallows '.' and ':' in session names (target syntax separators);
    # tmux silently rewrites them to '_' on create, breaking later lookups.
    pname="${pname//./_}"
    pname="${pname//:/_}"
    printf 'vms_%s\n' "$pname"
}

# ---------------------------------------------------------------------------
# Port allocation
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# Iterate over (profile_name, profile_dir) tab-separated lines.
each_profile() {
    require_prj
    shopt -s nullglob
    local pdir name psh
    for pdir in "$PRJ"/profiles/*/; do
        psh="${pdir}profile.sh"
        [ -f "$psh" ] || continue
        name="$(basename "$pdir")"
        printf '%s\t%s\n' "$name" "${pdir%/}"
    done
    shopt -u nullglob
}

# Iterate over (profile_name, vm_name, vm_dir) tab-separated lines.
each_vm() {
    require_prj
    shopt -s nullglob
    local pdir vdir pname vname
    for pdir in "$PRJ"/profiles/*/; do
        pname="$(basename "$pdir")"
        for vdir in "$pdir"vms/*/; do
            [ -d "$vdir" ] || continue
            [ -f "$vdir/vm.sh" ] || continue
            vname="$(basename "$vdir")"
            printf '%s\t%s\t%s\n' "$pname" "$vname" "${vdir%/}"
        done
    done
    shopt -u nullglob
}

# Source profile.sh in a subshell with parent env inherited; emit KEY=value lines.
read_profile_info() {
    local psh="$1"
    (
        set +e
        ARCH= LLVM= FS= KSRC= KOBJ= KIMAGE=
        # shellcheck disable=SC1090
        source "$psh" 2>/dev/null || true
        printf 'ARCH=%s\n'   "${ARCH:-}"
        printf 'LLVM=%s\n'   "${LLVM:-}"
        printf 'FS=%s\n'     "${FS:-}"
        printf 'KSRC=%s\n'   "${KSRC:-}"
        printf 'KOBJ=%s\n'   "${KOBJ:-}"
        printf 'KIMAGE=%s\n' "${KIMAGE:-}"
    )
}

# ---------------------------------------------------------------------------
# Subcommand: ls
# ---------------------------------------------------------------------------

cmd_ls() {
    local json_mode=false
    [ "${1:-}" = "--json" ] && json_mode=true

    require_prj
    local rows=()
    while IFS= read -r line; do
        rows+=("$line")
    done < <(each_profile)

    if "$json_mode"; then
        printf '['
        local first=true r name pdir psh info_lines arch llvm fs ksrc kobj kimage
        for r in "${rows[@]}"; do
            $first || printf ','
            first=false
            name="${r%%$'\t'*}"
            pdir="${r#*$'\t'}"
            psh="$pdir/profile.sh"
            info_lines="$(read_profile_info "$psh")"
            arch="$(  printf '%s\n' "$info_lines" | sed -n 's/^ARCH=//p')"
            llvm="$(  printf '%s\n' "$info_lines" | sed -n 's/^LLVM=//p')"
            fs="$(    printf '%s\n' "$info_lines" | sed -n 's/^FS=//p')"
            ksrc="$(  printf '%s\n' "$info_lines" | sed -n 's/^KSRC=//p')"
            kobj="$(  printf '%s\n' "$info_lines" | sed -n 's/^KOBJ=//p')"
            kimage="$(printf '%s\n' "$info_lines" | sed -n 's/^KIMAGE=//p')"
            printf '{"name":"%s","dir":"%s","arch":"%s","llvm":"%s","fs":"%s","ksrc":"%s","kobj":"%s","kimage":"%s"}' \
                "$name" "$pdir" "$arch" "$llvm" "$fs" "$ksrc" "$kobj" "$kimage"
        done
        printf ']\n'
        return 0
    fi

    if [ "${#rows[@]}" -eq 0 ]; then
        info "No profiles under $PRJ/profiles/"
        return 0
    fi
    # One line per profile, in order: PROFILE  KSRC  KOBJ_OR_KIMAGE  ARCH  LLVM  FS
    # Path values use $PRJ prefix substitution for readability.
    printf '%-20s %-35s %-45s %-7s %-5s %s\n' \
        "PROFILE" "KSRC" "KOBJ_OR_KIMAGE" "ARCH" "LLVM" "FS"
    local r name pdir psh info_lines arch llvm fs ksrc kobj kimage kob_or_kim
    for r in "${rows[@]}"; do
        name="${r%%$'\t'*}"
        pdir="${r#*$'\t'}"
        psh="$pdir/profile.sh"
        info_lines="$(read_profile_info "$psh")"
        arch="$(  printf '%s\n' "$info_lines" | sed -n 's/^ARCH=//p')"
        llvm="$(  printf '%s\n' "$info_lines" | sed -n 's/^LLVM=//p')"
        fs="$(    printf '%s\n' "$info_lines" | sed -n 's/^FS=//p')"
        ksrc="$(  printf '%s\n' "$info_lines" | sed -n 's/^KSRC=//p')"
        kobj="$(  printf '%s\n' "$info_lines" | sed -n 's/^KOBJ=//p')"
        kimage="$(printf '%s\n' "$info_lines" | sed -n 's/^KIMAGE=//p')"
        if [ -n "$kimage" ]; then
            kob_or_kim="$kimage"
        else
            kob_or_kim="$kobj"
        fi
        printf '%-20s %-35s %-45s %-7s %-5s %s\n' \
            "$name" \
            "$(prettify_path "${ksrc:--}")" \
            "$(prettify_path "${kob_or_kim:--}")" \
            "${arch:--}" "${llvm:--}" \
            "$(prettify_path "${fs:--}")"
    done
}

# ---------------------------------------------------------------------------
# Subcommand: ps
# ---------------------------------------------------------------------------

cmd_ps() {
    local json_mode=false
    [ "${1:-}" = "--json" ] && json_mode=true

    require_prj
    local rows=()
    while IFS= read -r line; do
        rows+=("$line")
    done < <(each_vm)

    local alive=()
    local r pname vname vdir pid sp gp st kim
    for r in "${rows[@]}"; do
        IFS=$'\t' read -r pname vname vdir <<<"$r"
        pid="$(read_pid "$vdir")"
        if is_pid_alive "$pid"; then
            sp="$( vm_meta_get "$vdir/vm.sh" SSH_PORT)"
            gp="$( vm_meta_get "$vdir/vm.sh" GDB_PORT)"
            st="$( vm_meta_get "$vdir/vm.sh" VM_STARTED_AT)"
            kim="$(vm_meta_get "$vdir/vm.sh" VM_KERNEL_IMAGE)"
            alive+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$pname" "$vname" "$sp" "$gp" "$pid" "$st" "$kim")")
        fi
    done

    if "$json_mode"; then
        printf '['
        local first=true rec
        for rec in "${alive[@]}"; do
            $first || printf ','
            first=false
            IFS=$'\t' read -r pname vname sp gp pid st kim <<<"$rec"
            printf '{"profile":"%s","vm":"%s","ssh_port":"%s","gdb_port":"%s","pid":"%s","started":"%s","kernel_image":"%s"}' \
                "$pname" "$vname" "$sp" "$gp" "$pid" "$st" "$kim"
        done
        printf ']\n'
        return 0
    fi

    if [ "${#alive[@]}" -eq 0 ]; then
        info "No running VMs"
        return 0
    fi
    # One line per VM, in order: PROFILE  VM  SSH_PORT  GDB_PORT  PID  KERNEL
    # KERNEL path uses $PRJ prefix substitution for readability.
    printf '%-20s %-10s %-9s %-9s %-7s %s\n' \
        "PROFILE" "VM" "SSH_PORT" "GDB_PORT" "PID" "KERNEL"
    local rec
    for rec in "${alive[@]}"; do
        IFS=$'\t' read -r pname vname sp gp pid st kim <<<"$rec"
        printf '%-20s %-10s %-9s %-9s %-7s %s\n' \
            "$pname" "$vname" "$sp" "$gp" "$pid" "$(prettify_path "$kim")"
    done
}

# ---------------------------------------------------------------------------
# Subcommand: run
# ---------------------------------------------------------------------------

cmd_run() {
    local vm_name=""
    local enable_shared=false
    local enable_kaslr=false
    local android_mode=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --shared)  enable_shared=true; shift ;;
            --kaslr)   enable_kaslr=true;  shift ;;
            --android) android_mode=true;  shift ;;
            --) shift; break ;;
            -*) error "Unknown run option: $1"; exit 2 ;;
            *)
                if [ -z "$vm_name" ]; then
                    vm_name="$1"; shift
                else
                    error "Unexpected positional arg: $1"; exit 2
                fi ;;
        esac
    done
    if [ -z "$vm_name" ]; then
        error "usage: vm.sh run <vm_name> [--shared] [--kaslr] [--android]"
        exit 2
    fi
    require_profile

    : "${ARCH:?ARCH not set in profile}"
    : "${FS:?FS not set in profile}"
    if [ ! -f "$FS/bookworm.img" ]; then
        error "Image not found: $FS/bookworm.img"
        exit 1
    fi

    # Resolve kernel image (variant A or B)
    local kernel_image=""
    if [ -n "${KIMAGE:-}" ]; then
        kernel_image="$KIMAGE"
    else
        if [ -z "${KOBJ:-}" ]; then
            error "Profile has neither KIMAGE nor KOBJ; cannot resolve kernel image."
            exit 1
        fi
        case "$ARCH" in
            arm64) kernel_image="$KOBJ/arch/arm64/boot/Image" ;;
            *)     kernel_image="$KOBJ/arch/x86/boot/bzImage" ;;
        esac
    fi
    if [ ! -f "$kernel_image" ]; then
        error "Kernel image not found: $kernel_image"
        exit 1
    fi
    kernel_image="$(realpath "$kernel_image")"

    # VM directory under current profile
    local vdir="$PROFILE/vms/$vm_name"
    mkdir -p "$vdir"

    # Reject if vm name is already alive in this profile.
    local prev_pid
    prev_pid="$(read_pid "$vdir")"
    if is_pid_alive "$prev_pid"; then
        error "VM '$vm_name' is already running (pid=$prev_pid). Run 'vm.sh kill' first."
        exit 1
    fi

    # Allocate SSH/GDB pair
    local SSH_P GDB_P
    if ! SSH_P=$(allocate_port_pair); then
        error "No free SSH/GDB port pair in 25000-29999"
        exit 1
    fi
    GDB_P=$(( SSH_P - 20000 ))

    local LOG_FILE="$vdir/boot.log"
    local PID_FILE="$vdir/vm.pid"
    local MON_FILE="$vdir/qemu.mon"
    local META_FILE="$vdir/vm.sh"

    # Wipe stale dynamic files; truncate boot.log.
    rm -f "$PID_FILE" "$MON_FILE"
    : > "$LOG_FILE"

    # vmlinux for gdb (best effort)
    local vmlinux=""
    if [ -n "${KOBJ:-}" ] && [ -f "$KOBJ/vmlinux" ]; then
        vmlinux="$KOBJ/vmlinux"
    fi

    # Write vm.sh metadata
    {
        printf '# auto-generated by vm.sh run; do not edit\n'
        printf 'export SSH_PORT=%s\n' "$SSH_P"
        printf 'export GDB_PORT=%s\n' "$GDB_P"
        printf 'export VM_STARTED_AT=%q\n'   "$(date -Iseconds)"
        printf 'export VM_KERNEL_IMAGE=%q\n' "$kernel_image"
        printf 'export VM_VMLINUX=%q\n'      "$vmlinux"
        printf 'export VM_KSRC=%q\n'         "${KSRC:-}"
        printf 'export VM_KOBJ=%q\n'         "${KOBJ:-}"
        printf 'export VM_FS=%q\n'           "$FS"
        printf 'export VM_LOG=%q\n'          "$LOG_FILE"
    } > "$META_FILE"

    IO_URING="sysctl.kernel.io_uring_disabled=2"
    USERNS="sysctl.user.max_user_namespaces=1"

    # Build QEMU args (x86_64 only for now)
    local QEMU_BIN=qemu-system-x86_64
    local KAPPEND="console=ttyS0 root=/dev/vda earlyprintk=serial net.ifnames=0 page_poison=1 kasan_multi_shot panic=0 no_hash_pointers acpi=noirq oops=oops $USERNS $IO_URING"
    if [ "$enable_kaslr" = "false" ]; then
        KAPPEND="$KAPPEND nokaslr"
    fi
    # --android: device-matched runtime (Pixel 10, 6.6.82-android15). Sets
    # cpu/mem/cmdline to mirror the device. Profile vars SMP/MEM still win
    # (set only when unset here), so a profile can override per case.
    if [ "$android_mode" = "true" ]; then
        : "${SMP:=8}"
        : "${MEM:=12G}"
        KAPPEND="$KAPPEND rcu_nocbs=all rcupdate.rcu_expedited=1"
    fi
    # Optional profile overrides (default-preserving): SMP, MEM, EXTRA_CMDLINE
    if [ -n "${EXTRA_CMDLINE:-}" ]; then
        KAPPEND="$KAPPEND $EXTRA_CMDLINE"
    fi
    local QEMU_ARGS=(
        -m "${MEM:-3.5G}"
        -cpu host
        -smp "${SMP:-2}"
        -kernel "$kernel_image"
        -append "$KAPPEND"
        -drive "file=$FS/bookworm.img,format=raw,snapshot=on,if=virtio"
        -nic "user,model=virtio-net-pci,hostfwd=tcp::${SSH_P}-:22"
        -chardev "stdio,id=char0,mux=on,signal=off,logfile=$LOG_FILE,logappend=off"
        -serial "chardev:char0"
        -enable-kvm
        -nographic
        -pidfile "$PID_FILE"
        -monitor "unix:$MON_FILE,server,nowait"
        -gdb "tcp::${GDB_P}"
    )
    if [ "$enable_shared" = "true" ]; then
        : "${SHARE:?SHARE not set; source scripts/env.sh first}"
        mkdir -p "$SHARE"
        QEMU_ARGS+=(
            -fsdev "local,security_model=passthrough,id=fsdev0,path=$SHARE/"
            -device "virtio-9p-pci,fsdev=fsdev0,mount_tag=host_share"
        )
    fi

    # tmux launch
    if ! command -v tmux >/dev/null 2>&1; then
        error "tmux not found; cannot launch VM in background."
        exit 1
    fi
    local SESSION
    SESSION="$(tmux_session_for_profile)"
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux new-session -d -s "$SESSION" -n "shell" "bash"
    fi
    # If a stale window with this vm_name exists (from a prior dead VM), close it.
    if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$vm_name"; then
        tmux kill-window -t "$SESSION:$vm_name" 2>/dev/null || true
    fi

    local QEMU_CMD="$QEMU_BIN" a
    for a in "${QEMU_ARGS[@]}"; do
        QEMU_CMD+=" $(printf '%q' "$a")"
    done
    local WINDOW_CMD="$QEMU_CMD; ec=\$?; echo; echo '[VM exited (status='\$ec'); press Enter to close]'; read -r _"

    tmux new-window -t "$SESSION:" -n "$vm_name" -d "$WINDOW_CMD"

    # Wait for QEMU to write its pidfile (or fail)
    local QEMU_PID=0 i
    for i in $(seq 1 40); do
        if [ -s "$PID_FILE" ]; then
            QEMU_PID="$(cat "$PID_FILE" 2>/dev/null || echo 0)"
            if [[ "$QEMU_PID" =~ ^[0-9]+$ ]] && [ "$QEMU_PID" -gt 0 ]; then
                break
            fi
            QEMU_PID=0
        fi
        if ! tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$vm_name"; then
            error "tmux window '$SESSION:$vm_name' vanished before QEMU started; check $LOG_FILE"
            exit 1
        fi
        sleep 0.25
    done
    if [ "$QEMU_PID" -eq 0 ]; then
        warn "QEMU did not write a readable pidfile within 10s."
        warn "Inspect: tmux attach -t $SESSION:$vm_name  /  tail $LOG_FILE"
    fi

    # Banner + next-step hint to stdout
    cat <<EOF
=================================================
 PROFILE:  $(basename "$PROFILE")
 VM:       $vm_name
 KERNEL:   $kernel_image
 KSRC:     ${KSRC:-<none>}
 KOBJ:     ${KOBJ:-<none>}
 FS:       $FS
 SSH_PORT: $SSH_P
 GDB_PORT: $GDB_P
 PID:      $QEMU_PID
 LOG:      $LOG_FILE
 TMUX:     $SESSION:$vm_name
 SHARED:   $([ "$enable_shared" = "true" ] && echo "on ($SHARE → /mnt/host_share)" || echo "off")
 KASLR:    $([ "$enable_kaslr" = "true" ] && echo "on" || echo "off (nokaslr)")
 CPU/MEM:  ${SMP:-2} cpu / ${MEM:-3.5G}
 ANDROID:  $([ "$android_mode" = "true" ] && echo "on (rcu_nocbs=all, rcu_expedited)" || echo "off")
=================================================
Run: envlx --vm $vm_name
EOF
}

# ---------------------------------------------------------------------------
# Subcommands: ssh / scp / gdb / attach / kill / rm / log
# ---------------------------------------------------------------------------

# Inspect $VM/boot.log to classify why an SSH connection failed.
# Prints a one-line tag + short excerpt to stderr; returns a category code:
#   251 = unreachable (everything that's not a panic: booting, login-up-but-
#                      SSH-down, network issue, hang, kdb, …)
#   252 = panic       (kernel panic / oops / BUG / GPF in boot.log)
diagnose_vm_state() {
    local log="$VM/boot.log"
    local tail=""
    if [ -f "$log" ]; then
        tail="$(tail -c 16384 "$log" 2>/dev/null || true)"
    fi

    if printf '%s\n' "$tail" | grep -qE 'Kernel panic|Oops:|BUG: |general protection fault|Unable to handle kernel'; then
        error "[panic] kernel panic/oops detected in boot.log:"
        printf '%s\n' "$tail" | grep -E 'Kernel panic|Oops:|BUG: |RIP:|Call Trace:|---\[ end' | tail -8 >&2
        return 252
    fi

    error "[unreachable] VM not accepting SSH (still booting / sshd down / network / hang / …)"
    if [ -n "$tail" ]; then
        printf '%s\n' "$tail" | tail -3 | sed 's/^/             /' >&2
    fi
    return 251
}

cmd_ssh() {
    require_vm
    : "${SSH_PORT:?SSH_PORT not set}"
    : "${FS:?FS not set}"
    # Require `--` before the remote command (if any) so the parser is
    # unambiguous and remote commands can freely start with '-'.
    if [ "$#" -gt 0 ]; then
        if [ "$1" != "--" ]; then
            error "Usage: vm.sh ssh [-- <cmd>...]"
            error "Put '--' before the remote command, e.g. vm.sh ssh -- ls -al"
            return 2
        fi
        shift
    fi
    local key="$FS/bookworm.id_rsa"
    if [ ! -f "$key" ]; then
        error "SSH key not found: $key"
        return 1
    fi
    local opts=(
        -p "$SSH_PORT"
        -i "$key"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ConnectTimeout=1
    )
    [ "$#" -gt 0 ] && opts+=(-t)
    local rc=0
    ssh "${opts[@]}" root@localhost "$@" || rc=$?
    # ssh exit 255 = connection failure (not a remote command exit).
    # In that case, diagnose against boot.log and surface a category code.
    if [ "$rc" -eq 255 ]; then
        diagnose_vm_state || rc=$?
    fi
    return "$rc"
}

cmd_scp() {
    require_vm
    : "${SSH_PORT:?SSH_PORT not set}"
    : "${FS:?FS not set}"
    if [ "$#" -lt 2 ]; then
        error "usage: vm.sh scp <src> <dst>  (use 'vm:/path' for the remote side)"
        exit 1
    fi
    local args=() a
    for a in "$@"; do
        case "$a" in
            vm:*) args+=("root@localhost:${a#vm:}") ;;
            *)    args+=("$a") ;;
        esac
    done
    exec "$SCRIPT_DIR/scp.sh" "${args[@]}"
}

cmd_gdb() {
    require_vm
    : "${GDB_PORT:?GDB_PORT not set}"
    # Resolve vmlinux: VM metadata → $KOBJ/vmlinux → alongside $KIMAGE → in $KSRC
    local vmlinux=""
    if [ -n "${VM_VMLINUX:-}" ] && [ -f "${VM_VMLINUX}" ]; then
        vmlinux="$VM_VMLINUX"
    elif [ -n "${KOBJ:-}" ] && [ -f "$KOBJ/vmlinux" ]; then
        vmlinux="$KOBJ/vmlinux"
    elif [ -n "${KIMAGE:-}" ] && [ -f "$(dirname "$KIMAGE")/vmlinux" ]; then
        vmlinux="$(dirname "$KIMAGE")/vmlinux"
    elif [ -n "${KSRC:-}" ] && [ -f "$KSRC/vmlinux" ]; then
        vmlinux="$KSRC/vmlinux"
    fi
    local args=()
    if [ -n "$vmlinux" ]; then
        args+=(-ex "file $vmlinux")
    else
        warn "vmlinux not found; gdb will attach without symbols."
    fi
    # Source path mapping: prefer KSRC, fall back to KOBJ (out-of-tree builds).
    if [ -n "${KSRC:-}" ] && [ -d "$KSRC" ]; then
        args+=(-ex "directory $KSRC")
    fi
    if [ -n "${KOBJ:-}" ] && [ -d "$KOBJ" ] && [ "${KOBJ:-}" != "${KSRC:-}" ]; then
        args+=(-ex "directory $KOBJ")
    fi
    args+=(-ex "target remote :$GDB_PORT")
    exec gdb "${args[@]}"
}

cmd_attach() {
    require_vm
    local SESSION vname
    SESSION="$(tmux_session_for_profile)"
    vname="$(basename "$VM")"
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        error "tmux session '$SESSION' not found"
        exit 1
    fi
    if ! tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$vname"; then
        error "tmux window '$SESSION:$vname' not found"
        exit 1
    fi
    if [ -n "${TMUX:-}" ]; then
        exec tmux switch-client -t "$SESSION:$vname"
    fi
    exec tmux attach -t "$SESSION:$vname"
}

cmd_kill() {
    require_vm
    local pid
    pid="$(read_pid "$VM")"
    if is_pid_alive "$pid"; then
        info "Killing VM (pid=$pid)..."
        kill -KILL "$pid" 2>/dev/null || true
    else
        info "VM PID is not alive; nothing to kill (vm.pid: ${pid:-(empty)})."
    fi
    local SESSION vname
    SESSION="$(tmux_session_for_profile)"
    vname="$(basename "$VM")"
    if tmux has-session -t "$SESSION" 2>/dev/null && \
       tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$vname"; then
        tmux kill-window -t "$SESSION:$vname" 2>/dev/null || true
    fi
    rm -f "$VM/vm.pid" "$VM/qemu.mon"
}

cmd_rm() {
    require_vm
    if [ "$#" -gt 0 ]; then
        error "rm takes no positional args; target is -v <vm_name>"
        exit 2
    fi
    local pid
    pid="$(read_pid "$VM")"
    if is_pid_alive "$pid"; then
        error "VM '$(basename "$VM")' is still running (pid=$pid). Run 'vm.sh kill' first."
        exit 1
    fi
    case "$VM" in
        "$PRJ"/profiles/*/vms/*) ;;
        *)
            error "Refusing to rm outside profiles/*/vms/: $VM"
            exit 1 ;;
    esac
    rm -rf "$VM"
    info "Removed $VM"
}

cmd_log() {
    require_vm
    local f="$VM/boot.log"
    if [ ! -f "$f" ]; then
        error "boot.log not found: $f"
        exit 1
    fi
    exec tail -f "$f"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

# Parse top-level -p/-v flags (must come before the subcommand).
PROFILE_ARG=""
VM_ARG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--profile)
            if [ "$#" -lt 2 ]; then error "-p requires <profile>"; exit 2; fi
            PROFILE_ARG="$2"; shift 2 ;;
        -v|--vm)
            if [ "$#" -lt 2 ]; then error "-v requires <vm>"; exit 2; fi
            VM_ARG="$2"; shift 2 ;;
        -h|--help|help) usage; exit 0 ;;
        --) shift; break ;;
        -*) error "Unknown global option: $1"; usage; exit 2 ;;
        *) break ;;
    esac
done

require_prj

# Resolve -p → PROFILE / PROFILE_SH + load profile.sh
if [ -n "$PROFILE_ARG" ]; then
    PROFILE="$PRJ/profiles/$PROFILE_ARG"
    PROFILE_SH="$PROFILE/profile.sh"
    if [ ! -d "$PROFILE" ]; then
        error "Profile directory missing: $PROFILE"
        exit 1
    fi
    if [ ! -f "$PROFILE_SH" ]; then
        error "profile.sh missing: $PROFILE_SH"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$PROFILE_SH"
    export PROFILE PROFILE_SH
fi

# Resolve -v → VM / VM_SH + load vm.sh metadata
if [ -n "$VM_ARG" ]; then
    if [ -z "$PROFILE_ARG" ]; then
        error "-v requires -p"; exit 2
    fi
    VM="$PROFILE/vms/$VM_ARG"
    VM_SH="$VM/vm.sh"
    if [ ! -d "$VM" ]; then
        error "VM directory missing: $VM"
        exit 1
    fi
    if [ ! -f "$VM_SH" ]; then
        error "VM metadata missing: $VM_SH"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$VM_SH"
    export VM VM_SH
fi

# Subcommand dispatch
if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

cmd="$1"; shift
case "$cmd" in
    -h|--help|help) usage ;;
    ls)             cmd_ls       "$@" ;;
    ps)             cmd_ps       "$@" ;;
    run)            cmd_run      "$@" ;;
    ssh)            cmd_ssh      "$@" ;;
    scp)            cmd_scp      "$@" ;;
    gdb)            cmd_gdb      "$@" ;;
    attach)         cmd_attach   "$@" ;;
    kill)           cmd_kill     "$@" ;;
    rm)             cmd_rm       "$@" ;;
    log)            cmd_log      "$@" ;;
    *) error "Unknown command: $cmd"; usage; exit 2 ;;
esac
