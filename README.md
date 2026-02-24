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
cp .env.example .env
# If your UID/GID is not 1000, edit .env accordingly
# Check: id -u && id -g

# 2. Build & start
docker compose up -d

# 3. Enter the container
docker compose exec -u dev kernel-dev bash

# 4. Build a kernel inside the container
cd /workspace
wget -qO- https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.71.tar.xz | tar xJf - -C kernels/

SRC=linux-6.12.71 OBJ=debug source scripts/envsetup.sh
make -C $KSRC O=$KOBJ defconfig
make -C $KSRC O=$KOBJ -j$(nproc)
```

### Stop

```bash
docker compose down
```

### SSH Access

```bash
# Password-less SSH into the container
ssh -p 2222 dev@localhost

# SSH port is configurable via SSH_PORT in .env (default: 2222)
```

### Clipboard

Uses OSC 52 escape sequences, which work through any number of SSH hops (e.g., Windows → Server → Docker).

```bash
# Copy to local clipboard
pwd | clip

# Works from SSH too
ssh -p 2222 dev@localhost
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

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_UID` | 1000 | Host user UID (`id -u`) |
| `HOST_GID` | 1000 | Host user GID (`id -g`) |
| `SSH_PORT` | 2222 | SSH port forwarded to host |

### Notes

- Missing `.env` file will show a setup guide on container start.
- The `dev` user inside the container matches your host UID/GID, avoiding file ownership issues.
- The project directory is bind-mounted to `/workspace`. Host file changes are reflected immediately.
- Runs in `privileged` mode for scripts using loopback devices (e.g., `create-image.sh`).
- The `dev` user has passwordless sudo.
- To customize dotfiles, edit files in `dotfiles/` and run `docker compose build`.

---
For more details, see the comments in `scripts/envsetup.sh` and the example commands in `commands.txt`.
