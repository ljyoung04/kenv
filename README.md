# Linux Kernel Project Environment Template

This repository provides a reusable, well-structured environment for any Linux kernel-related project. The main goal is to standardize and simplify the setup of environment variables and directory structures, making it easy to reuse and adapt for various kernel development, analysis, or research tasks.

## Directory Structure
- `kernels/`   : Linux kernel source trees
- `images/`    : Disk images for different architectures
- `configs/`   : Configuration files
- `scripts/`   : Utility scripts for building, running, and managing kernels/images
- `patches/`   : Patch files and related resources
- `share/`     : Shared files for VM or host-guest communication

## Environment Variables
The environment is managed via `scripts/envsetup.sh`. Key variables include:

- `ARCH`   : Target architecture (e.g., `arm64`, `x86_64`)
- `KSRC`   : Path to the kernel source directory
- `KOBJ`   : Path to the kernel build (object) directory
- `IMAGE`  : Path to the root filesystem image for the target architecture
- `SHARE`  : Path to the shared directory for host/guest file exchange
- `PRJ`    : Project root directory
- `SCRIPT_DIR` : Directory containing the environment scripts

These variables are automatically set and exported by sourcing `scripts/envsetup.sh` with the appropriate parameters. See the script for advanced usage and override logic.

## Example Workflow
See `commands.txt` for a typical workflow, including:
- Downloading a kernel source
- Creating disk images
- Setting up the environment
- Building the kernel
- Generating compile_commands.json

## Docker

Ready-to-use kernel build environment without host setup.

### Prerequisites

- Docker & Docker Compose

### Quick Start

```bash
# 1. Create .env (once)
./init.sh
# Detects UID/GID automatically and picks an available SSH port (2000-3000)

# 2. Build & start
docker compose up -d

# 3. Enter the container
docker compose exec -u compsec kernel-dev bash

# 4. Build a kernel inside the container
cd /workspace
wget -qO- https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.71.tar.xz | tar xJf - -C kernels/

SRC=linux-6.12.71 OBJ=debug source scripts/envsetup.sh
cp $CONFIGS/kernelctf.config $KOBJ/.config
make -C $KSRC O=$KOBJ olddefconfig
make -C $KSRC O=$KOBJ -j$(nproc)
make -C $KSRC O=$KOBJ scripts_gdb
$KSRC/scripts/clang-tools/gen_compile_commands.py -d $KOBJ -o $KSRC/compile_commands.json

```

### Filesystem Images

Create and manage root filesystem images for QEMU VMs.

```bash
# Create an x86_64 image (inside the container)
../../scripts/create-image.sh -d bookworm -s 20480 -a amd64
# → images/x64/bookworm.img

# Create an arm64 image
../../scripts/create-image.sh -d bookworm -s 20480 -a arm64
# → images/arm64/bookworm.img
```

Use `mkfs` to create new images easily:

```bash
# Create a default x86_64 image (5G, bookworm)
$ mkfs compsec
[*] Creating filesystem image: images/compsec/
[*] Arch: x86_64, Distro: bookworm, Size: 5120MB
...
[*] Cleaning up debootstrap directory...
[*] Created: images/compsec/bookworm.img (5.0G)
[*] FS: /workspace/images/compsec
```

Multiple images can coexist under `images/`. Use `lsfs` and `setfs` to manage them:

```bash
# List available images and their status
$ lsfs
  [x64] bookworm.img (2.0G, x86_64)
* [compsec] bookworm.img (5.0G, x86_64)
  [aarch64] bookworm.img (2.0G, aarch64)

# Select a filesystem image
$ setfs compsec
[*] FS: /workspace/images/compsec
```

FS is independent from kernel setup — you can build a kernel without setting FS, and switch FS freely between VM runs:

```bash
# Setup kernel only (no FS needed for build)
SRC=linux-6.12.71 OBJ=debug source scripts/envsetup.sh

# Build kernel
make -C $KSRC O=$KOBJ -j$(nproc)

# Pick an image and run
setfs compsec
$SCRIPTS/run-vm.sh -s # Launch VM with shared directory
```

### SSH into Container

Connection path: **Local → Server → Container**

```bash
# From server (docker host)
ssh -p 2222 compsec@localhost

# From local machine (jump proxy through server)
ssh -J user@server -p 2222 compsec@localhost
```

SSH port is configurable via `SSH_PORT` in `.env` (default: 2222).

### SSH/SCP into VM

Connection path: **Container → VM**

```bash
# SSH into the VM
ssh -p $SSH_PORT -i $FS/bookworm.id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost

# SCP files to the VM
scp -P $SSH_PORT -i $FS/bookworm.id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null scripts/tracer.sh root@localhost:/root/
```

### Guest Workflow

Inside the QEMU VM:

```bash
# Mount shared directory (host $SHARE ↔ guest /mnt)
mount -t 9p -o trans=virtio host_share /mnt

# Load ftrace helpers and see available commands
source tracer.sh
thelp
```

### Stop

```bash
docker compose down
```

### Clipboard

Uses OSC 52 escape sequences, which work through any number of SSH hops (e.g., Windows → Server → Docker).

```bash
# Copy to local clipboard
pwd | clip

# Works from SSH too
ssh -p 2222 compsec@localhost
$ echo hello | clip
```

> Supported terminals: Windows Terminal, VS Code terminal, iTerm2, Alacritty, etc.
> If clipboard doesn't work, check your terminal's OSC 52 setting is enabled.

### Pre-installed Tools

- LLVM/Clang-19
- GDB 17.1 (with fzf Ctrl+R history search patch)
- bata24/gef
- oh-my-bash, smart-bash-history, zoxide
- fzf, ripgrep, fd, bat, eza, tree
- htop, tmux, jq, strace, ltrace
- vim, net-tools, openssh-server

### `.env` Configuration

Run `./init.sh` to generate `.env` automatically. It detects your UID/GID and picks an available SSH port in 2000-3000.

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_UID` | 1000 | Host user UID (auto-detected via `id -u`) |
| `HOST_GID` | 1000 | Host user GID (auto-detected via `id -g`) |
| `SSH_PORT` | 2222 | SSH port forwarded to host (auto-selected) |

### Notes

- Missing `.env` file will show a setup guide on container start.
- The `compsec` user inside the container matches your host UID/GID, avoiding file ownership issues.
- The project directory is bind-mounted to `/workspace`. Host file changes are reflected immediately.
- Runs in `privileged` mode for scripts using loopback devices (e.g., `create-image.sh`).
- The `compsec` user has passwordless sudo.
- To customize dotfiles, edit files in `dotfiles/` and run `docker compose build`.

---
For more details, see the comments in `scripts/envsetup.sh` and the example commands in `commands.txt`.
