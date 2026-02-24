#!/bin/bash

if [ -z "$_READY" ]; then
    echo "[-] run env.sh first"
    echo "source env.sh"
    exit 1
fi

# --- FS validation ---
if [ -z "$FS" ] || [ "$FS" == "" ]; then
    echo "[-] FS not set. Available filesystem images:"
    echo ""
    lsfs 2>/dev/null || ls -1d "$IMAGES"/*/ 2>/dev/null
    echo ""
    echo "[-] Use 'setfs <name>' to select a filesystem image, then re-run."
    exit 1
fi

if [ ! -f "$FS/bookworm.img" ]; then
    echo "[-] Image not found: $FS/bookworm.img"
    exit 1
fi

if fuser "$FS/bookworm.img" >/dev/null 2>&1; then
    echo "[!] WARNING: $FS/bookworm.img is in use by another process."
    echo "[!] Running multiple QEMU instances on the same image may cause corruption."
    read -p "Continue anyway? [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Print environment variables ---
echo "================================================="
echo "KSRC:     $KSRC"
echo "KOBJ:     $KOBJ"
echo "SHARE:    $SHARE"
echo "FS:       $FS"
echo "SSH_PORT: $SSH_PORT"
echo "GDB_PORT: $GDB_PORT"
echo "================================================="
echo

ENABLE_FSDEV=false
ENABLE_PAGE_TABLE_CHECK=false
ENABLE_STOP=false
ENABLE_KASLR=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: run.sh [--shared|-s] [--page-check|-p] [-S] [-k]"
            exit 0
            ;;
        -k)
            ENABLE_KASLR=true
            shift
            ;;
        -S)
            ENABLE_STOP=true
            shift
            ;;
        --shared|-s)
            ENABLE_FSDEV=true
            shift
            ;;
        --page-check|-p)
            ENABLE_PAGE_TABLE_CHECK=true
            shift
            ;;
        *)
            echo "Not supported option: $1"
            exit 1
            ;;
    esac
done

QEMU_BIN=qemu-system-x86_64

KERNEL_APPEND="console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0 page_poison=1 kasan_multi_shot panic=0 sysctl.user.max_user_namespaces=0"
KERNEL_APPEND="$KERNEL_APPEND no_hash_pointers"
# KERNEL_APPEND="$KERNEL_APPEND isolcpus=managed,domain,1 nohz_full=1,domain,1 rcu_nocbs=1 acpi=noirq"
if [ "$ENABLE_KASLR" = "false" ]; then
    KERNEL_APPEND="$KERNEL_APPEND nokaslr"
fi
# KERNEL_APPEND="$KERNEL_APPEND preempt=full"


if [ "$ENABLE_PAGE_TABLE_CHECK" = "true" ]; then
    KERNEL_APPEND="$KERNEL_APPEND page_table_check=on"
fi

QEMU_COMMAND=(
    "sudo" "$QEMU_BIN"
    -m 4g
    -cpu host
    -smp 2
    -kernel "$KOBJ/arch/x86/boot/bzImage"
    -append "$KERNEL_APPEND"
    -drive "file=$FS/bookworm.img,format=raw"
    -nic user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22
)
    # -net "user,host=10.0.2.10,hostfwd=tcp:127.0.0.1:20202-:22"
    # -net "nic,model=e1000"

if [ "$ENABLE_FSDEV" = "true" ]; then
    QEMU_COMMAND+=(
        -fsdev "local,security_model=passthrough,id=fsdev0,path=$SHARE/"
        -device "virtio-9p-pci,fsdev=fsdev0,mount_tag=host_share"
    )
fi

QEMU_COMMAND+=(
    -enable-kvm
    -nographic
    -pidfile vm.pid
    -gdb tcp::${GDB_PORT}
)

if [ "$ENABLE_STOP" = "true" ]; then
    QEMU_COMMAND+=("-S")
fi

"${QEMU_COMMAND[@]}" 2>&1
#| tee vm.log