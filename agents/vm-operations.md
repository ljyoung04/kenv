# VM and kernel operations

Read this for VM lifecycle, kernel builds, guest commands, transfers, debugging,
or profiles. Every separate Bash invocation starts with:

```bash
source /workspace/scripts/env.sh
```

## Canonical commands

```bash
"$SCRIPTS/vm.sh" ls --json
"$SCRIPTS/vm.sh" ps --json
"$SCRIPTS/vm.sh" -p <profile> run <task>_<unix-timestamp> [--kaslr]
"$SCRIPTS/kernel.sh" -p <profile> --build [-j <jobs>]
"$SCRIPTS/kernel.sh" -p <profile> --olddefconfig
"$SCRIPTS/kernel.sh" -p <profile> --kctfconfig
"$SCRIPTS/kernel.sh" -p <profile> --clang
"$SCRIPTS/vm.sh" -p <profile> -v <vm> ssh -- <command> [args...]
"$SCRIPTS/vm.sh" -p <profile> -v <vm> scp <src> <dst>
"$SCRIPTS/vm.sh" -p <profile> -v <vm> gdb
"$SCRIPTS/vm.sh" -p <profile> -v <vm> attach
"$SCRIPTS/vm.sh" -p <profile> -v <vm> log
"$SCRIPTS/vm.sh" -p <profile> -v <vm> kill
"$SCRIPTS/vm.sh" -p <profile> -v <vm> rm
```

Discovery needs no scope flags. Builds default to 16 jobs. `--kctfconfig`
replaces `$KOBJ/.config`; preserve a needed config first. `--clang` generates
`compile_commands.json` and `.clangd`. Profiles define `ARCH`, `LLVM`, `FS`,
and either `KSRC` + `KOBJ` or `KIMAGE`.

Use `kasan` for reproduction and memory-safety diagnostics and `kernelctf` for
final target work. A profile name does not prove current official-target parity.

Guest paths use `vm:`:

```bash
"$SCRIPTS/vm.sh" -p kasan -v <vm> scp "$SHARE/<research>/poc" vm:/tmp/poc
"$SCRIPTS/vm.sh" -p kasan -v <vm> scp vm:/tmp/result.log "$SHARE/<research>/logs/result.log"
```

VM state lives under `$PRJ/profiles/<profile>/vms/<vm>/`. `vm.pid` is the
liveness source of truth; preserve `boot.log`. GDB uses the profile `vmlinux`
and recorded port.

## SSH results

| Code | Meaning | Handling |
| --- | --- | --- |
| `0` | Guest command succeeded | Continue |
| `251` | Unavailable, booting, hung, KDB, or services unavailable | Inspect diagnostics; retry only when justified |
| `252` | Panic, oops, BUG, or GPF in `boot.log` | Preserve and diagnose |
| `1`–`250`, `253`, `254` | Guest command status | Treat as program result |
| `255` | Other transport/client failure | Diagnose transport/client |

Bound retries. Repeated `251` does not prove boot progress.

