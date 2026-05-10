# CLAUDE.md — agent guide for `linux-env`

`linux-env` is a QEMU/KVM kernel dev environment with a Docker-style
**profile (image) + vm (container)** model. State lives on disk; shell
context is just env vars.

## First thing you do, every session

```bash
source /home/jjy/project/linux-env/scripts/env.sh
```

This sets the project globals (below) and defines the shell helpers. After
that, **always use environment variables** to refer to project paths
(e.g. `$SCRIPTS/vm.sh`, `$CONFIGS/.clangd`, `$VM/boot.log`); avoid hardcoding
`scripts/...` or absolute paths.

## Environment variables

After `source /home/jjy/project/linux-env/scripts/env.sh`:

| Var          | Value                              |
|--------------|------------------------------------|
| `$PRJ`       | project root                       |
| `$SCRIPTS`   | `$PRJ/scripts`                     |
| `$CONFIGS`   | `$PRJ/configs`                     |
| `$IMAGES`    | `$PRJ/images`                      |
| `$SHARE`     | `$PRJ/share` (host↔guest 9p share) |
| `$SYZKALLER` | `$PRJ/syzkaller`                   |

After `--profile <p>`:

| Var | Required? | Notes |
|-----|-----------|-------|
| `$PROFILE`     | (auto)    | directory `$PRJ/profiles/<p>/` |
| `$PROFILE_SH`  | (auto)    | `$PROFILE/profile.sh` |
| `$ARCH`        | required  | `x86_64`, `arm64`, … |
| `$LLVM`        | required  | `1`, `-19`, `0`(=gcc) |
| `$FS`          | required  | root-fs dir (e.g. `$IMAGES/x64`) |
| `$KSRC`        | A: req / B: opt | kernel source tree |
| `$KOBJ`        | A: req    | kernel build dir |
| `$KIMAGE`      | B: req    | prebuilt bzImage |

Variant A = build from source (`KSRC`+`KOBJ`). Variant B = use prebuilt
bzImage (`KIMAGE`).

After `--vm <v>`:

| Var          | Notes |
|--------------|-------|
| `$VM`        | directory `$PROFILE/vms/<v>/` |
| `$VM_SH`     | `$VM/vm.sh` |
| `$SSH_PORT`  | host SSH port |
| `$GDB_PORT`  | host gdbstub port |

VM PID is in `$VM/vm.pid` (file, not env), serial console in `$VM/boot.log`.

## Minimal end-to-end workflow

```bash
source /home/jjy/project/linux-env/scripts/env.sh   # initial setup (mandatory), set global vars and helpers

source $SCRIPTS/env.sh --profile <p>                # enter profile (template auto-created if absent)
$SCRIPTS/kernel.sh --build                          # Variant A: build kernel
$SCRIPTS/vm.sh run <v>                              # boot a VM under current profile
source $SCRIPTS/env.sh --profile <p> --vm <v>       # enter both scopes
$SCRIPTS/vm.sh ssh <cmd...>                         # remote command (no `--` separator)
$SCRIPTS/vm.sh log                                  # tail -f $VM/boot.log
$SCRIPTS/vm.sh kill                                 # stop QEMU; preserves $VM/boot.log
$SCRIPTS/vm.sh rm                                   # delete $VM/ (refuses live VM)
```

Discovery (no context required):

```bash
$SCRIPTS/vm.sh ls --json    # registered profiles
$SCRIPTS/vm.sh ps --json    # live VMs across all profiles
```

## More detail

TODO