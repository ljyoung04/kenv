# AGENTS.md — Agent Guide for `kenv`

`kenv` is a QEMU/KVM-based Linux kernel development environment using a
Docker-style **profile (image) + VM (container)** model.

Persistent state lives on disk. The command-line interfaces, `vm.sh` and
`kernel.sh`, are **strict and stateless**:

* Profile scope is always passed explicitly with `-p <profile>`.
* VM scope is always passed explicitly with `-v <vm>`.
* Profile or VM selection must never be inherited from environment variables,
  shell aliases, or previous commands.

## 1. Environment Initialization

Every Bash invocation must source `env.sh` before using project paths or
scripts:

```bash
source /workspace/scripts/env.sh
```

This initializes the following path variables:

```text
$PRJ
$SCRIPTS
$CONFIGS
$IMAGES
$SHARE
$SYZKALLER
```

Do not rely on profile or VM state that may have been selected previously with
interactive helpers such as `envlx`.

## 2. Canonical Invocation

Every command must be self-contained.

### Discovery

Discovery commands do not require profile or VM flags:

```bash
$SCRIPTS/vm.sh ls --json
$SCRIPTS/vm.sh ps --json
```

* `ls --json` lists registered profiles.
* `ps --json` lists VMs whose recorded QEMU PID is alive in `/proc`.

### Profile-scoped operations

The `-p <profile>` argument is required:

```bash
$SCRIPTS/vm.sh -p <profile> run <task>_$(date +%s) [--shared] [--kaslr]

$SCRIPTS/kernel.sh -p <profile> --build [-j <jobs>]
$SCRIPTS/kernel.sh -p <profile> --olddefconfig
$SCRIPTS/kernel.sh -p <profile> --kctfconfig
$SCRIPTS/kernel.sh -p <profile> --clang
```

Notes:

* `--build` uses 16 jobs by default.
* `--kctfconfig` copies `$CONFIGS/kernelctf.config` to `$KOBJ/.config`.
* `--clang` generates `compile_commands.json` and `.clangd`.

### VM-scoped operations

Both `-p <profile>` and `-v <vm>` are required:

```bash
$SCRIPTS/vm.sh -p <profile> -v <vm> ssh -- <command> [args...]
$SCRIPTS/vm.sh -p <profile> -v <vm> scp <src> <dst>
$SCRIPTS/vm.sh -p <profile> -v <vm> gdb
$SCRIPTS/vm.sh -p <profile> -v <vm> attach
$SCRIPTS/vm.sh -p <profile> -v <vm> log
$SCRIPTS/vm.sh -p <profile> -v <vm> kill
$SCRIPTS/vm.sh -p <profile> -v <vm> rm
```

For `ssh`, the `--` separator before the remote command is mandatory.

For `scp`, prefix a remote path with `vm:`:

```bash
$SCRIPTS/vm.sh -p kasan -v repro_1722345678 \
    scp "$SHARE/repro/poc" vm:/tmp/poc

$SCRIPTS/vm.sh -p kasan -v repro_1722345678 \
    scp vm:/tmp/result.log "$SHARE/repro/result.log"
```

## 3. VM Naming

Agents must name every VM using:

```text
<task>_<unix-timestamp>
```

Examples:

```bash
vm_name="repro-cve50264_$(date +%s)"
$SCRIPTS/vm.sh -p kasan run "$vm_name"

vm_name="bisect-netfilter_$(date +%s)"
$SCRIPTS/vm.sh -p kasan run "$vm_name"
```

Generic names such as the following are reserved for the user and must not be
used by agents:

```text
a
vm
vm1
test
debug
```

Timestamped names prevent collisions with user-created VMs and VMs created by
other agents.

## 4. Starting and Connecting to a VM

Do not use interactive profile or VM selection as part of an agent workflow.

Select the profile explicitly according to the current research phase:

* Use `kasan` for vulnerability reproduction and memory-safety validation.
* Use `kernelctf` for final exploit development under KernelCTF constraints.

Example:

```bash
source /workspace/scripts/env.sh

profile="kasan"
vm_name="repro-epoll_$(date +%s)"

$SCRIPTS/vm.sh -p "$profile" run "$vm_name"

$SCRIPTS/vm.sh -p "$profile" -v "$vm_name" ssh -- uname -a
```

If the guest is still booting, retry only when `ssh` returns `251`.

For debugging:

```bash
$SCRIPTS/vm.sh -p "$profile" -v "$vm_name" gdb
```

The `gdb` command automatically loads the profile's `vmlinux` and uses the
GDB port recorded in the VM metadata.

## 5. `vm.sh ssh` Exit Codes

Agents must branch on the following return codes:

|             Return code | Meaning                                                                                    |
| ----------------------: | ------------------------------------------------------------------------------------------ |
|                     `0` | SSH connection succeeded and the remote command returned success                           |
|                   `251` | Guest is unreachable, still booting, hung, in KDB, or SSH/network services are unavailable |
|                   `252` | A kernel panic, oops, BUG, or GPF was detected in `boot.log`                               |
| `1`–`250`, `253`, `254` | Exit status returned by the remote command                                                 |
|                   `255` | SSH transport or client failure not classified as `251` or `252`                           |

When diagnosis is available, `vm.sh` prints a short status tag and a relevant
`boot.log` excerpt to stderr.

Do not interpret every nonzero return code as an unreachable VM. For example,
a remote program returning `1` must be treated as a program failure rather
than an SSH failure.

## 6. State on Disk

```text
$PRJ/profiles/<profile>/profile.sh
$PRJ/profiles/<profile>/vms/<vm>/vm.sh
$PRJ/profiles/<profile>/vms/<vm>/vm.pid
$PRJ/profiles/<profile>/vms/<vm>/boot.log
```

Meaning:

* `profile.sh`: static profile configuration
* `vm.sh`: generated VM metadata, including SSH and GDB ports
* `vm.pid`: QEMU PID and the single source of truth for liveness
* `boot.log`: serial console output

A profile must define:

```text
ARCH
LLVM
FS
```

It must additionally use one of the following variants.

### Variant A — Build from source

```text
KSRC
KOBJ
```

### Variant B — Prebuilt kernel

```text
KIMAGE
```

A missing `profile.sh` may be created from the template with:

```bash
source "$SCRIPTS/env.sh" --profile <profile>
```

This command may initialize profile files, but it does not remove the
requirement to pass `-p <profile>` explicitly to every subsequent CLI
invocation.

## 7. File and Data Transfer Rules

All source code, PoCs, exploits, logs, and research notes created by an agent
must be stored under `$SHARE`.

Recommended layout:

```text
$SHARE/<research-name>/
├── README.md
├── poc.c
├── exploit.c
├── Makefile
├── logs/
└── artifacts/
```

The QEMU shared-directory feature must not be used to expose `$SHARE` directly
inside the guest.

In particular:

* Do not start a VM with `--shared` for vulnerability validation or exploit
  development unless the user explicitly instructs otherwise.
* Do not access host files through a mounted 9p, virtiofs, or equivalent shared
  filesystem.
* Transfer files between the host and guest only with:

```bash
$SCRIPTS/vm.sh -p <profile> -v <vm> scp <src> <dst>
```

Thus, `$SHARE` is the host-side authoritative workspace, while `vm scp` is the
transport mechanism.

## 8. Vulnerability Research Requirements

Unless the user explicitly specifies another procedure, use the following
workflow.

### 8.1 Respect KernelCTF constraints

Before evaluating a candidate, identify the interfaces available in the target
KernelCTF environment.

Do not base an exploit strategy on functionality disabled by the KernelCTF
rules or target configuration. Examples may include:

```text
io_uring
nftables
unprivileged user namespaces(unshare)
```

The actual target configuration and current KernelCTF rules take precedence
over assumptions.

### 8.2 Perform lifecycle-oriented code analysis

Explore the selected subsystem logically rather than performing only
pattern-based searches.

Prioritize:

* object allocation, initialization, publication, and destruction
* reference-count ownership and transfer
* error-path cleanup
* asynchronous work and callbacks
* RCU and deferred destruction
* timer lifetime
* file-descriptor lifetime
* namespace teardown
* cancellation and timeout paths
* user-controlled sizes, indexes, offsets, and flags
* interactions between syscalls, ioctls, netlink, procfs, sysfs, and mmap
* concurrency between user-controlled operations

Consider vulnerability classes including:

* use-after-free
* double free
* race condition
* reference-count error
* out-of-bounds access
* integer overflow or truncation
* uninitialized memory use
* type confusion
* stale pointer use
* incorrect locking
* missing validation
* lifetime mismatch between related objects

Prefer candidates with a realistic path to memory corruption or privilege
escalation.

### 8.3 Create a minimal reproducer

Once a credible candidate is identified:

1. Document the suspected root cause.
2. Write the smallest practical reproducer under `$SHARE`.
3. Start a uniquely named VM using the `kasan` profile.
4. Copy the reproducer into the guest with `vm.sh scp`.
5. Run it repeatedly.
6. Preserve the complete serial log and KASAN report under `$SHARE`.

A crash is not sufficient by itself. Confirm that the report corresponds to
the suspected bug rather than an unrelated failure introduced by the
reproducer.

### 8.4 Check whether the bug is already known

After reproducing the bug, and before investing substantial effort in exploit
development, search for prior reports using:

* syzbot and syzkaller dashboards
* Linux kernel mailing lists
* public Git commits and stable backports
* CVE and security-advisory databases
* public exploit and PoC repositories
* the relevant subsystem's issue tracker, if one exists

Classify the result as follows:

* **Duplicate or already fixed:** document the match and stop pursuing it as a
  new vulnerability.
* **Public one-day vulnerability:** continue only when the user requested
  one-day analysis or when it remains useful for KernelCTF exploit practice.
* **Apparently unreported vulnerability:** continue toward exploitability
  analysis while preserving evidence and avoiding premature public disclosure.
* **Uncertain:** document the potentially related reports and explain why the
  match could not be confirmed.

Do not claim that a vulnerability is new solely because a CVE number was not
found.

Reference link : https://docs.google.com/spreadsheets/d/e/2PACX-1vS1REdTA29OJftst8xN5B5x8iIUcxuK6bXdzF8G1UXCmRtoNsoQ9MbebdRdFnj6qZ0Yd7LwQfvYC2oF/pubhtml

### 8.5 Evaluate exploitability

Determine whether the primitive can be made reliable under the target
configuration.

Evaluate:

* attacker-controlled allocation and free timing
* target cache and object size
* allocator behavior
* cross-cache reclaim feasibility
* attacker control over overwritten data
* information disclosure requirements
* KASLR bypass
* SMEP, SMAP, KPTI, CFI, and allocator hardening
* available replacement objects
* privilege-escalation target
* reproducibility across boots

Use materials under the following directory when relevant:

```text
$SHARE/kctf/security-research/pocs/linux/kernelctf
```

Do not modify reference PoCs in place. Copy any material that must be adapted
into the current research directory.

### 8.6 Develop the KernelCTF exploit

Move to the `kernelctf` profile only after:

* the root cause is understood;
* the KASAN reproducer is stable;
* the bug is not disqualified as an unwanted duplicate; and
* a plausible exploitation strategy has been identified.

Create a new uniquely named `kernelctf` VM and transfer all files with
`vm.sh scp`.

The final exploit must respect the target's actual KernelCTF configuration and
rules.

Use:

```text
$SHARE/kernel-research/libxdk
```

for KASLR-base acquisition unless the user explicitly requires another
technique.

Do not hard-code a kernel base obtained from a single run.

## 9. Persistence and Termination Criteria

Continue investigation while there are concrete, technically justified next
steps.

Do not stop merely because:

* the first reproducer did not trigger;
* an initial heap layout was unstable;
* one reclaim object failed;
* one race window was too narrow; or
* the first exploit strategy failed.

Try multiple reasonable approaches, such as:

* adjusting scheduling and CPU affinity
* widening or instrumenting race windows
* changing heap grooming
* testing alternative reclaim objects
* inspecting the relevant state with GDB
* comparing neighboring kernel versions
* reducing the reproducer
* validating assumptions through kernel instrumentation

Terminate the operation when one of the following conditions is met:

1. The exploit succeeds reliably under the required profile.
2. The bug is confirmed to be a duplicate that should not be pursued.
3. The relevant primitive is unavailable under KernelCTF constraints.
4. Multiple technically distinct exploitation strategies have failed and
   evidence supports the conclusion that practical exploitation is not
   feasible.
5. The candidate is determined not to be a vulnerability.
6. Further work requires information, access, or capabilities that are not
   available in the environment.

When terminating, prepare a final report containing:

* target subsystem and kernel revision
* root cause
* affected object lifecycle
* triggering sequence
* reproducer location
* crash or KASAN evidence
* prior-report search results
* exploit primitive
* mitigations and constraints
* attempted strategies
* success or failure result
* remaining uncertainties
* exact artifact paths

## 10. VM Cleanup

Use:

```bash
$SCRIPTS/vm.sh -p <profile> -v <vm> kill
```

to stop QEMU while preserving the VM directory and logs.

Use:

```bash
$SCRIPTS/vm.sh -p <profile> -v <vm> rm
```

to delete a stopped VM directory.

`rm` must refuse to delete a VM whose recorded QEMU PID is still alive.

Preserve VMs that contain evidence required for the final report unless disk
usage or an explicit user instruction requires deletion.

## 11. Prohibited Actions

Do not:

* modify or invoke `$SCRIPTS/envsetup.sh`;
* modify or invoke `$SCRIPTS/run-vm.sh`;
* depend on interactive `envlx` profile or VM state;
* omit `-p` or `-v` because a shell helper appears to remember them;
* use generic VM names;
* use QEMU shared folders for PoC or exploit transfer;
* read or rely on files under `$PRJ/reports/`;
* read or rely on files under `$PRJ/agents/`;
* overwrite unrelated user files;
* modify reference PoCs in place;
* treat stale output from another agent as authoritative.

`$SCRIPTS/envsetup.sh` and `$SCRIPTS/run-vm.sh` are legacy reference files
only.

## 12. Response and Report Formatting

Wrap file paths in backticks.

When referring to a specific line, format it as a backticked path followed by a
colon and the line number:

```text
`scripts/vm.sh`:120
`share/repro/poc.c`:87
```

Do not place the line number inside the backticks.

Commands should be shown in fenced `bash` blocks. Logs and directory layouts
should be shown in fenced `text` blocks unless another language is more
appropriate.

## 13. Additional Documentation

For human-oriented usage examples and project context, refer to:

```text
$PRJ/commands.txt
$PRJ/README.md
```

`$PRJ/commands.txt` may use the interactive `vm` and `kernel` shell functions
defined by `env.sh`. Agents must translate those examples into the explicit,
stateless `vm.sh -p ... -v ...` and `kernel.sh -p ...` forms described in this
document.
