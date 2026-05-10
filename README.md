# linux-env

A streamlined Linux kernel development and debugging environment built around
QEMU/KVM, with a Docker-style **profile + vm** model.

> Define a *profile* once (which kernel, which root fs, which arch), then
> spin up named *VMs* on top of it for boot, SSH, gdb, fuzzing, exploit
> work, etc. No more dragging `SRC=…`, `OBJ=…`, `SSH_PORT=…` through every
> shell.

---

## Why

If you regularly:

- build several Linux kernel versions side by side,
- boot any of them under QEMU with KVM acceleration,
- SSH/scp/gdb into the running guests,
- keep multiple guests alive in parallel,

…this repo replaces the usual ad-hoc shell scripting with a small,
predictable surface:

| You want to…              | You run…                                       |
|---------------------------|------------------------------------------------|
| Define a kernel/fs combo  | edit `profiles/<name>/profile.sh` (auto-template generated) |
| Enter that combo          | `source scripts/env.sh --profile <name>`       |
| Boot a fresh VM under it  | `scripts/vm.sh run <vm_name>`                  |
| Drop into the running VM  | `scripts/vm.sh ssh`                            |
| Build the kernel          | `scripts/kernel.sh --build`                    |
| List everything alive     | `scripts/vm.sh ps`                             |

---

## Concepts

The vocabulary borrows directly from Docker:

| Docker            | linux-env             | On disk                              |
|-------------------|-----------------------|--------------------------------------|
| Image (immutable) | **profile**           | `profiles/<p>/profile.sh`            |
| Container         | **vm**                | `profiles/<p>/vms/<v>/`              |
| `docker images`   | `vm.sh ls`            | —                                    |
| `docker ps`       | `vm.sh ps`            | —                                    |
| `docker run`      | `vm.sh run <vm_name>` | —                                    |

A profile is a small shell file. Two flavors:

- **Variant A — build from source.** You set `KSRC` (kernel tree) and
  `KOBJ` (build dir). `scripts/kernel.sh --build` produces the bzImage.
- **Variant B — prebuilt bzImage.** You set `KIMAGE` directly. Useful for
  CTF/release images. `KSRC` is optional (gdb source mapping only).

Both variants require `ARCH`, `LLVM`, `FS` (root-fs image dir).

---

## Quick start

### 1. Get the helpers into every shell (optional but recommended)

Add a single line to `~/.bashrc`:

```bash
envlx() { source /path/to/linux-env/scripts/env.sh "$@"; }
```

The first time you call `envlx`, it sources `scripts/env.sh`, which exports
project globals (`$PRJ`, `$SCRIPTS`, `$CONFIGS`, `$IMAGES`, `$SHARE`,
`$SYZKALLER`), defines `vm`/`lsfs`/`setfs`/`mkfs`/`vmhttp` helpers, and
overrides this shim with the real `envlx`. After that, `envlx` and `vm` work
in any shell.

If you don't want shell helpers, just `source scripts/env.sh` directly when
you need them — every snippet below works either way.

### 2. Define your first profile

```bash
envlx --profile lts-6.12
# → "Profile 'lts-6.12' does not exist."
# → "Creating template at: .../profiles/lts-6.12/profile.sh"
# → "Edit it, then run: source $SCRIPTS/env.sh --profile lts-6.12"
$EDITOR $PRJ/profiles/lts-6.12/profile.sh
```

Variant A example (build from source):

```sh
export ARCH=x86_64
export LLVM=1
export FS="$IMAGES/x64"
export KSRC="$PRJ/kernels/linux-6.12.y"
export KOBJ="$KSRC/build/debug"
```

Variant B example (use a release bzImage):

```sh
export ARCH=x86_64
export LLVM=1
export FS="$IMAGES/x64"
export KIMAGE="$PRJ/kctf/releases/lts-6.12.79/bzImage"
```

### 3. Build the kernel (Variant A)

```bash
envlx --profile lts-6.12
kernel.sh --olddefconfig
kernel.sh --build               # default -j 16, override with -j N
kernel.sh --clang               # optional: compile_commands.json + .clangd
```

To start from kernelctf's base config:

```bash
kernel.sh --kctfconfig          # cp $CONFIGS/kernelctf.config $KOBJ/.config
kernel.sh --olddefconfig
kernel.sh --build
```

### 4. Boot a VM, drop into it

```bash
vm run a                        # boot a VM named 'a'
                                # output ends with: "Run: envlx --vm a"
envlx --vm a                    # SSH_PORT, GDB_PORT load into your shell
vm ssh                          # interactive SSH into the guest
vm ssh uname -a                 # one-shot remote command
vm log                          # tail -f $VM/boot.log
```

### 5. Run a second VM in parallel

```bash
vm run b                        # auto-allocates a different SSH/GDB pair
vm ps                           # both 'a' and 'b' shown
envlx --vm b                    # switch shell context to 'b'
vm ssh hostname
```

### 6. Tear down

```bash
vm kill                         # stop QEMU; keep $VM/boot.log for later analysis
vm rm                           # delete the $VM directory entirely
                                # (refuses if the VM is still alive)
```

---

## Reference

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/env.sh`     | Source-only entry point. Handles `--profile`/`--vm`/`--reset`, sets globals, defines helpers. |
| `scripts/vm.sh`      | VM lifecycle: `ls`/`ps`/`run`/`ssh`/`scp`/`gdb`/`attach`/`kill`/`rm`/`log`. |
| `scripts/kernel.sh`  | Kernel build/config: `--menuconfig`/`--olddefconfig`/`--kctfconfig`/`--build [-j N]`/`--clang`. |
| `scripts/envsetup.sh`, `scripts/run-vm.sh` | Legacy entry points kept for reference. New code does not call them. |

### Filesystem images

```bash
lsfs                            # list available images under $IMAGES
setfs <name>                    # set $FS to $IMAGES/<name> (current shell)
mkfs <name> [-a arch] [-s MB]   # create a new image (debootstrap-based)
```

`$FS` is normally part of the profile (defined in `profile.sh`), but `setfs`
is handy for one-off experiments.

### tmux integration

Each VM runs inside a tmux session/window in the background:

- Session name: `vms_<profile_name>` (`.` and `:` in the profile name are
  rewritten to `_`; tmux uses them as target separators)
- Window name: `<vm_name>`

```bash
vm attach                       # tmux attach -t vms_<p>:<vm_name>
```

### Per-VM state files

Under `$PROFILE/vms/<vm_name>/`:

| File | Contents |
|------|----------|
| `vm.sh`    | sourceable: `SSH_PORT`, `GDB_PORT`, `VM_KERNEL_IMAGE`, `VM_FS`, … |
| `vm.pid`   | QEMU PID — single source of truth for liveness |
| `boot.log` | serial console output |
| `qemu.mon` | QEMU monitor unix socket |

`vm.sh ps` reads `vm.pid` and checks `/proc/$PID` for liveness; it does
**not** auto-prune dead directories — that lets you post-mortem a crash.
Use `vm.sh rm` to clean up explicitly.

### JSON output

For scripts/agents:

```bash
vm ls --json
vm ps --json
```

### Restoring a context in another shell

`envlx` (no args) prints the current scope and ends with a `Restore:` line
you can copy/paste into another terminal:

```
Restore: source $SCRIPTS/env.sh --profile lts-6.12 --vm a
```

---

## Layout overview

```
linux-env/
├── kernels/<name>/             # kernel source trees you've cloned/extracted
├── images/<name>/bookworm.img  # root-fs images (mkfs / create-image.sh)
├── profiles/<name>/            # profile definitions
│   ├── profile.sh              # static config (sourced by env.sh)
│   └── vms/<vm_name>/          # per-VM dynamic state (vm.sh, vm.pid, boot.log)
├── configs/                    # kernel configs, .clangd template
├── share/                      # host↔guest 9p share
├── syzkaller/                  # syzkaller workspace
├── scripts/
│   ├── env.sh, vm.sh, kernel.sh    # main entry points
│   ├── envsetup.sh, run-vm.sh      # legacy (reference only)
│   ├── ssh.sh, scp.sh              # internal helpers used by vm.sh
│   ├── shell-init.sh               # optional bashrc shim
│   └── create-image.sh, .common.sh
├── commands.txt                # annotated workflow examples
├── README.md                   # this file
└── CLAUDE.md                   # agent-facing operating guide
```

---

## Docker (optional)

If you'd rather not install LLVM-19 / QEMU / debootstrap on your host, this
repo ships a development container with everything pre-installed.

```bash
./init.sh                       # generate .env (UID/GID detection, SSH port)
docker compose up -d
docker compose exec -u compsec kernel-dev bash
```

Inside the container, the profile/vm workflow above is identical. The
project directory is bind-mounted to `/workspace`.

Pre-installed inside the container:

- LLVM/Clang-19, GDB 17.1 (with [bata24/gef][gef]), tmux, jq
- fzf, ripgrep, fd, bat, eza, tree, zoxide
- htop, strace, ltrace, vim, openssh-server

[gef]: https://github.com/bata24/gef

### SSH chain

```
local machine  ─ssh→  server  ─docker exec→  container  ─vm.sh ssh→  QEMU guest
```

Container SSH port (host → container) is configurable via `.env`'s
`SSH_PORT` (default 2222, auto-picked by `init.sh`).

---

## Notes

- `scripts/envsetup.sh` and `scripts/run-vm.sh` are kept as a reference for
  the legacy "single global VM" workflow. They still work standalone if you
  need them, but the new flow does not call them. Eventually they'll be
  removed.
- `prompt_init`, `prompt_output`, `prompt_final` in the repo root document
  the design rationale that led to the current profile/vm model. They're
  not workflow docs — read them only if you're curious about *why*.
- `commands.txt` is the agent-friendly cheat-sheet of working snippets.

---

## Acknowledgements

Built around standard tooling: QEMU/KVM, debootstrap, LLVM/Clang, tmux,
gdb (+ bata24/gef). The profile/vm CLI shape is loosely modelled on Docker.
