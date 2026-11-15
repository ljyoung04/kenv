---
name: dynamic-validation
description: Validate kernel vulnerability candidates from static analysis with minimal reproducers and runtime evidence (KASAN, KCSAN, KFENCE, WARN, lockdep) in an isolated, task-owned kenv VM. Use for candidate reproduction, crash causality checks, and weeding out static false positives; hand confirmed defects to patch-generation.
---

# Dynamic Validation

Take candidates from `vuln-discovery`. For each one, establish whether the
defect occurs at runtime and whether it comes from the designated root cause.
Deliver a minimal reproducer, original evidence, a causal analysis, and an
explicit verdict with its limits.

## Scope

- Read root `AGENTS.md`, `scope.md`, and the candidate records first.
- Run this stage only when the user asked for runtime validation. A
  discovery-only request does not authorize running reproducers.
- Write and minimize reproducers that **trigger and observe** the defect,
  and nothing more.
- Write artifacts to `agent/<research-name>/validation/<candidate-id>/`. Keep
  the original Candidate-ID and Target-ID. Do not edit discovery records.
- Work candidates one at a time by default. With subagents (only if the user
  asks), give each worker its own candidate, output path, VM, and build dir.

## 1. Intake

For each candidate, confirm:

- Exact revision, config, entry point, attacker control, required privileges
- Violated invariant, the expected **first invalid operation**, source lines
- Static falsification results and open assumptions
- What observation proves success, and how it will be captured

Do not treat `SOURCE_CONFIRMED` as a runtime fact. For a `HYPOTHESIS`, close
the missing static evidence first. If the source or config needed is not
available, mark the candidate `NEEDS_CONTEXT`. Do not keep re-running a
candidate that was clearly falsified unless new evidence appears.

Records in `agent/`, from this research or an earlier one, are inputs to
check, not facts. Before spending VM time, confirm that the record's
revision and config match the kernel you will build, re-hash its evidence,
and spot-check its cited `path:line` against the pinned source. A record
that fails any of these checks is treated like a `HYPOTHESIS`: close the
static gap first. An earlier `NOT_REPRODUCED` or `REJECTED` closes a
candidate only after you have checked its stated reason, such as budget, a
missing diagnostic, wrong privileges, or a wrong build.

Before running anything, set and record a per-candidate budget: wall time,
attempt count, guest CPU/memory, and a no-progress stopping rule. Do not
try to win long races or refcount wraparounds by exhausting host resources.

## 2. Environment

### Profiles and builds

- Discover profiles with `tools/vm.sh ls --json`. Do not guess.
- Validation usually needs a **sanitizer build** next to the target build.
  Use a separate profile and `KOBJ` (for example `<target>-kasan`) so the
  target build is never overwritten. Start from the target config, merge
  only the needed fragments (`configs/kasan_config`, `configs/debug_config`),
  then run `olddefconfig`. Record the effective diff from the target config.
- If a needed profile does not exist, create `profiles/<p>/profile.sh`
  explicitly, record that you created it, and keep the change minimal.
- Build with `tools/kernel.sh -p <p> --build -j <N>`. Record the compiler,
  the config SHA-256, and the `vmlinux`/`bzImage` SHA-256.

Choose diagnostics to fit the hypothesis:

| Hypothesis | Primary diagnostics | Notes |
|---|---|---|
| UAF / OOB | KASAN (generic), KFENCE | KASAN can miss accesses to `SLAB_TYPESAFE_BY_RCU` caches and some paths under spinlocks; `CONFIG_SLUB_RCU_DEBUG` changes reuse timing |
| Data race | KCSAN | A race report is not proof of memory corruption |
| Uninitialized memory or info leak | KMSAN (clang), or explicit leak markers | KMSAN cannot be combined with KASAN |
| Integer or UB | UBSAN | |
| Lock or refcount | lockdep, `REFCOUNT_FULL`-style WARNs, `DEBUG_OBJECTS` | |

Confirm that each diagnostic is actually enabled in the built `.config` and
at boot. Instrumentation, injected delays, and fault injection are
experimental conditions; record them as such. A change that alters kernel
logic to *create* the defect is not reproduction evidence.

When a sanitizer cannot see the bug (for example a `SLAB_TYPESAFE_BY_RCU`
object), use a different observation: a WARN in the free path, a
cross-cache invalid free, a poisoned sentinel, or ftrace on the alloc/free
sites. See `../human-report/references/example1.md` for a real case.

### VM

- Name the VM `<task>_<unix-timestamp>` (letters, digits, `_`, `-`). Check
  `profiles/<p>/vms/` for collisions, including stopped VMs.
- Boot with `tools/vm.sh -p <p> run <name>`. kenv uses `-enable-kvm -cpu host`.
  Do not fall back to TCG emulation without recording it, because emulator
  bugs can look like kernel bugs.
- Record profile, VM name, path, boot time, and the owning candidate in
  `environment.md`.
- Transfer files with `tools/vm.sh -p <p> -v <v> scp ./file vm:/path`. Use
  `--shared` only if the user asked for a shared host directory.
- Do not create images. If no suitable image exists, record the requirement
  and stop. Run `tools/tracer.sh` helpers only inside the guest.

`environment.md` records: source commit and local diff, config/vmlinux/bzImage
hashes, compiler and build commands, boot arguments (including
`nokaslr`/`--kaslr`), guest image, CPU and memory, and `uname -a` from the
guest. A `uname` string alone does not prove you booted the image you built;
compare the build ID or banner with your build.

### KernelCTF

Re-check the current rules and the required LTS trigger read-only. If the
rules require an LTS crash, run it as a **separate experiment** on the
matching LTS profile (for example `kernels/lts-<ver>` and `-kasan`), with its
own hashes. Keep KASAN-only crashes separate from crashes on the
uninstrumented LTS build. Remote runs need `kctf-official-helper` and
explicit user approval for that exact action.

## 3. Reproducer loop

1. Write a readable reproducer that contains only the operations needed
   from the attacker entry point to the faulty operation. Print every
   syscall return and `errno`, and print progress markers so you can tell
   where a run stopped.
2. Build on the host if convenient. Run it **only** in the guest. Save the
   compile command and the source/binary SHA-256.
3. Separate admin setup from attacker actions. Run the attacker part as the
   intended user (for example
   `vm.sh ... ssh -- su nobody -s /bin/sh -c ./poc`, or `setpriv`/`unshare`
   as the threat model needs). Record UID/GID, capabilities, and namespaces.
   A run from a root SSH session is not an unprivileged reproduction.
4. Capture console evidence on every run: copy `boot.log` (or tail it
   with `vm.sh ... log`) to `attempts/<run-id>/` before and after the run.
   Set a timeout on the remote command.
5. Interpret `vm.sh ssh` exit codes using the `AGENTS.md` table **and** the
   stderr text: 251 means SSH is unavailable, 252 means `boot.log` has
   panic/oops/BUG evidence. The remote command can also return those
   numbers itself.
6. On failure, compare the last progress marker with the expected path.
   Classify the failure: rejected input, missing config, missing privilege,
   timing, missing instrumentation, or infrastructure.
7. Change only what new observations justify. Log each attempt's change,
   reason, inputs, and result. Never overwrite earlier logs.

No KASAN report does not mean the code is safe. Check diagnostic coverage,
path reachability, attempt counts, and missed observations.

For races, pin threads to separate CPUs (`sched_setaffinity`) when the
window holds a spinlock or disables preemption. Give the guest enough vCPUs
(profile `SMP`), and report successes out of total attempts.

## 4. Causality

When a crash occurs, save the original evidence before running again.

- **Confirm that the report is your bug.** Match the first bad access
  (function, access type and size, object cache, offset) and the
  alloc/free stacks to the candidate's predicted first invalid operation.
  A crash elsewhere, or a different object, may be a **different bug**.
  Record it as a new finding, and do not count it as success.
- Symbolize with that build's `vmlinux`, using
  `scripts/decode_stacktrace.sh` or `vm.sh ... gdb`.
- Write the chain: input → state transition → invariant violation → observed
  report. Do not infer the root cause from a secondary crash after
  corruption, or from a one-line sanitizer summary.
- Keep infrastructure failures (QEMU, SSH, watchdog, OOM, wrong image)
  separate from candidate results.
- Minimize: remove unneeded calls, inputs, and threads, then re-run the final
  reproducer on a freshly booted VM. Record order, concurrency, seed,
  elapsed time, and successes out of total.
- Run a control with the key trigger condition removed. A clean control is
  supporting evidence, not proof by itself.

If minimizing loses the reproduction, keep the last version that reproduced.

## 5. Impact class (evidence only)

For each confirmed defect, record a short, evidence-bound classification to
order patch work.

- Observed effect, as the diagnostic reports it (for example "UAF write of
  8 bytes at offset 160 in kmalloc-192", "8 bytes of uninitialized stack
  copied to user")
- Class: memory corruption / info leak / DoS-only / logic or permission bypass
- Reachability actually demonstrated (privileges, namespaces)
- Anything beyond that is `UNVERIFIED`

## Verdicts

Keep the static status and add `Validation-status`:

| Status | Criteria |
|---|---|
| `DYNAMIC_CONFIRMED` | Defect observed in the recorded environment, linked to the designated root cause, with original evidence and steps |
| `OBSERVED_UNATTRIBUTED` | Abnormal behavior observed, but not causally linked to this candidate |
| `NOT_REPRODUCED` | Not reproduced within the recorded conditions and budget. This does not falsify the candidate |
| `REJECTED` | Concrete evidence falsifies it (impossible precondition, real defense) |
| `NEEDS_CONTEXT` | Required source, config, environment, or privilege info is missing |
| `INFRA_BLOCKED` | Image, boot, tooling, or resource problems prevented a valid experiment |

`DYNAMIC_CONFIRMED` covers only the demonstrated environment. One occurrence
is enough if the evidence and causality hold, but state the repeatability
limits.

## Completion

Stop a candidate when it is confirmed and attributed, falsified, out of
budget, or blocked. Continue with the other candidates.

```text
validation/<candidate-id>/
  environment.md      target, config diff, privileges, VM ownership, diagnostics
  repro/              final reproducer, build and run steps
  attempts/<run-id>/  commands, inputs, outputs, console/kernel logs, stop reason
  validation.md       causality, verdict, repeatability, impact class, limits
  SHA256SUMS
```

`validation.md` includes Candidate-ID, Target-ID, the static record path,
`Validation-status`, observations, source links, demonstrated privileges,
differences between target and experiment, successes out of total, notable
failures, and unverified impacts.

Merge the results into `FINDINGS.md`. Kill VMs you no longer need with
`vm.sh -p <p> -v <v> kill`, and keep their directories as evidence. Hand
`DYNAMIC_CONFIRMED` candidates to `patch-generation` only if that stage was
requested.

## Background

Adapted from the Triage stage of OpenAI's
[A thousand fewer paths to root](https://openai.com/index/a-thousand-fewer-paths-to-root/):
minimal PoCs run in VMs with a KASAN debug kernel, so that only reproduced
candidates move on. The post notes two failure modes that this skill guards
against explicitly: a run that "succeeds" through a *different* bug than
the one assigned, and a test-infrastructure (QEMU TCG) bug.
