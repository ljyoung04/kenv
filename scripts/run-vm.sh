#!/bin/bash

if [ -z "$_READY" ]; then
    echo "[-] run env.sh first"
    echo "source env.sh"
    exit 1
fi

# --- Print environment variables ---
echo "================================================="
echo "KSRC:  $KSRC"
echo "KOBJ:  $KOBJ"
echo "SHARE: $SHARE"
echo "IMAGE: $IMAGE"
echo "================================================="
echo

ENABLE_FSDEV=false
ENABLE_PAGE_TABLE_CHECK=false
ENABLE_STOP=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: run.sh [--shared|-s] [--page-check|-p] [-S]"
            exit 0
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

KERNEL_APPEND="console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0 nokaslr page_poison=1"

if [ "$ENABLE_PAGE_TABLE_CHECK" = "true" ]; then
    KERNEL_APPEND="$KERNEL_APPEND page_table_check=on"
fi

QEMU_COMMAND=(
    "sudo" "$QEMU_BIN"
    -m 4g
    -cpu host
    -smp 3
    -kernel "$KOBJ/arch/x86/boot/bzImage"
    -append "$KERNEL_APPEND"
    -drive "file=$IMAGE/bookworm.img,format=raw"
    -net "user,host=10.0.2.10,hostfwd=tcp:127.0.0.1:20202-:22"
    -net "nic,model=e1000"
)

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
    -gdb tcp::1245
)

if [ "$ENABLE_STOP" = "true" ]; then
    QEMU_COMMAND+=("-S")
fi

"${QEMU_COMMAND[@]}" 2>&1 | tee vm.log
