# AGENTS.md — agent guide for `kenv`

`kenv` is a QEMU/KVM kernel dev environment with a Docker-style
**profile (image) + vm (container)** model. State lives on disk; the CLI
(`vm.sh`, `kernel.sh`) is **strict and stateless** — profile/vm scope is
passed via `-p`/`-v` flags on every invocation, never inherited from env.

## How to invoke (agents)

Every command is self-contained. Pass `-p <profile>` (and `-v <vm>` when
operating on a specific VM) explicitly:

```bash
# Discovery (no flags)
$SCRIPTS/vm.sh ls --json                                    # registered profiles
$SCRIPTS/vm.sh ps --json                                    # live VMs (PID alive in /proc)

# Profile-scope operations (-p required)
$SCRIPTS/vm.sh -p <p> run <task>_$(date +%s) [--shared] [--kaslr]
$SCRIPTS/kernel.sh -p <p> --build [-j N]                    # default -j 16
$SCRIPTS/kernel.sh -p <p> --olddefconfig
$SCRIPTS/kernel.sh -p <p> --kctfconfig                      # cp $CONFIGS/kernelctf.config $KOBJ/.config
$SCRIPTS/kernel.sh -p <p> --clang                           # compile_commands.json + .clangd

# VM-scope operations (-p and -v required)
$SCRIPTS/vm.sh -p <p> -v <v> ssh -- <cmd...>                # '--' before remote cmd is required
$SCRIPTS/vm.sh -p <p> -v <v> scp <src> <dst>                # 'vm:/path' for remote side
$SCRIPTS/vm.sh -p <p> -v <v> gdb                            # auto-loads vmlinux
$SCRIPTS/vm.sh -p <p> -v <v> attach                         # tmux attach
$SCRIPTS/vm.sh -p <p> -v <v> log                            # tail -f $VM/boot.log
$SCRIPTS/vm.sh -p <p> -v <v> kill                           # stop QEMU; preserve directory
$SCRIPTS/vm.sh -p <p> -v <v> rm                             # delete vm directory (refuses live)
```

The globals `$PRJ`/`$SCRIPTS`/`$CONFIGS`/`$IMAGES`/`$SHARE`/`$SYZKALLER` are
set by `source $SCRIPTS/env.sh` once per shell — needed for the path
references above. Do that as the first line of any Bash invocation:

```bash
source /home/jjy/project/kenv/scripts/env.sh
```

## `vm.sh ssh` exit codes

For agent retry/branch logic:

| rc  | meaning                                                                |
|-----|------------------------------------------------------------------------|
| 0   | normal: connected, command succeeded                                   |
| 251 | unreachable (still booting / sshd down / network / hang / kdb / …)     |
| 252 | panic (kernel panic/oops/BUG/GPF detected in boot.log)                 |
| 1–254 | remote command's own non-zero exit                                   |

Diagnosis prints a short tag + boot.log excerpt to stderr.

## State on disk

```
$PRJ/profiles/<p>/profile.sh       static profile config
$PRJ/profiles/<p>/vms/<v>/vm.sh    SSH_PORT/GDB_PORT/kernel metadata
$PRJ/profiles/<p>/vms/<v>/vm.pid   QEMU PID (single source of truth)
$PRJ/profiles/<p>/vms/<v>/boot.log serial console
```

Profile required vars: `ARCH`, `LLVM`, `FS`, and either `KSRC`+`KOBJ`
(Variant A — build from source) or `KIMAGE` (Variant B — prebuilt bzImage).
A missing `profile.sh` is auto-created from a template by
`source $SCRIPTS/env.sh --profile <name>`.

## VM naming

Always use `<task>_<timestamp>` so collisions with the user's or other
agents' VMs are structurally impossible:

```bash
$SCRIPTS/vm.sh -p <p> run repro-cve50264_$(date +%s)
$SCRIPTS/vm.sh -p <p> run bisect_$(date +%s)
```

Generic names like `a`, `vm`, `vm1` belong to the user — never use them.

## Don't

- Don't modify or call `$SCRIPTS/envsetup.sh` / `$SCRIPTS/run-vm.sh` — legacy
  reference only.
- Don't read or rely on existing files under `$PRJ/reports/` or
  `$PRJ/agents/` (prior agent outputs, possibly stale).

## Response-format rule

File paths in backticks; `path:line` with backtick + colon. Example:
`` `scripts/vm.sh:120` ``.

## More detail

- `$PRJ/commands.txt` — copy/paste recipes (mostly human-flow via the `vm`
  and `kernel` shell functions defined in env.sh; agents stick to the
  flag-explicit form above)
- `$PRJ/README.md` — human-facing project intro
