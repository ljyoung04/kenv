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

Discovery needs no scope flags. Builds default to 16 jobs, but that default is
not a resource-safety guarantee: choose an explicit lower `-j` when host CPU or
memory pressure warrants it. `--kctfconfig` replaces `$KOBJ/.config`; copy a
needed config into the task artifact directory and record its hash first.
`--clang` generates `compile_commands.json` and `.clangd`. Profiles define
`ARCH`, `LLVM`, `FS`, and either `KSRC` + `KOBJ` or `KIMAGE`.
Profile and VM scope names may contain letters, digits, `.`, `_`, and `-`, and
must begin with a letter or digit; path components are rejected. `run` refuses
an existing VM directory, so use a fresh timestamped name after any collision.

Use a profile verified to enable KASAN for reproduction and memory-safety
diagnostics, and a profile verified against the current KernelCTF target for
final target work. Select its exact name from `vm.sh ls --json`; a profile name
alone does not prove current official-target parity. Record the
kernel/config/image hashes, launch options, and runtime restrictions. Because
`run` defaults to `nokaslr`, use `--kaslr` whenever target parity or the exploit
stage requires KASLR.

Guest paths use `vm:`:

```bash
"$SCRIPTS/vm.sh" -p <kasan-profile> -v <vm> scp "$SHARE/<research>/poc" vm:/tmp/poc
"$SCRIPTS/vm.sh" -p <kasan-profile> -v <vm> scp vm:/tmp/result.log "$SHARE/<research>/logs/result.log"
```

VM state lives under `$PRJ/profiles/<profile>/vms/<vm>/`. A live VM requires a
numeric `vm.pid` and a live QEMU process whose command line names that exact
VM's pidfile; a PID alone is not proof of liveness. Record ownership in the
research manifest and preserve `boot.log`. GDB uses the profile `vmlinux` and
recorded port.

## SSH results

| Code | Meaning | Handling |
| --- | --- | --- |
| `0` | Guest command succeeded | Continue |
| `1`–`250`, `253`, `254` | Usually the guest command status | Treat as a program result unless wrapper diagnostics say otherwise |
| `251` | Guest status 251, or wrapper-classified SSH failure when stderr contains `[unreachable]` | Use the diagnostic tag and current `boot.log`; do not infer from the number alone |
| `252` | Guest status 252, or wrapper-classified panic when stderr contains `[panic]` | Preserve the current log when the diagnostic tag is present |
| `255` | SSH's internal transport/client status; the wrapper normally translates it to 251 or 252 | Diagnose transport/client and do not use 255 as a test-program result |

Avoid 251, 252, and 255 in test-program exit-code contracts. Remote arguments
are passed directly; shell operators and redirection require an explicit guest
shell and careful quoting. Set a retry count and deadline before retrying.
Repeated `251` does not prove boot progress. `log`, `attach`, and `gdb` are
interactive or streaming commands; bound observation time and exit them when
the needed evidence is captured.

