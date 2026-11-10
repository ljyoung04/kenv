---
name: dynamic-validation
description: Validate kernel vulnerability candidates handed off from static analysis using minimal reproducers and runtime evidence such as KASAN/KCSAN in isolated, task-owned VMs. Use for candidate reproduction, crash causality checks, and identifying static-analysis false positives; hand exploit development and patch generation off to separate stages.
---

# Dynamic Validation

Accept candidates from [vuln-discovery](../vuln-discovery/SKILL.md) and verify whether the defect occurs at runtime and stems from the designated root cause. Deliver a minimal reproducer, original execution evidence, causal analysis, and an explicit verdict and limitations.

## Scope and Assignment

- First read `AGENTS.md`, the handed-off `scope.md`, and candidate records. Execute within the authorized dynamic-validation scope; do not infer permission to run reproducers from a discovery request alone.
- Write and modify minimal reproducers, run them in isolation, diagnose, and minimize. Privilege escalation, flag acquisition, mitigation bypass, and exploit-chain implementation are not completion requirements for this skill.
- Assign kernel validation to `kernel_astra` or the exact model `gpt-6-astra`. If already running as that model, perform it directly. Record the requested model separately from the verified actual model; do not substitute arbitrarily if unsupported.
- For parallel validation, assign exclusive workers, output paths, VMs, and build directories per candidate. Workers must not revert others' files. The orchestrator updates shared `FINDINGS.md`. Assign independent reviewers only to candidates needing a separate causality review.
- Preserve artifacts in `agent/<research-name>/validation/<candidate-id>/`. Do not overwrite discovery records; retain the original Candidate-ID and Target-ID.

## 1. Handoff and Reproduction Preparation

Check the following for each candidate:

- Exact source revision, configuration, entry point, attacker control, required privileges and state
- Violated invariant, expected first invalid operation, and relevant source locations
- Static falsification results, unverified assumptions, and duplicate/fix status
- Observations that establish successful reproduction and how to collect them

Do not treat even `SOURCE_CONFIRMED` as a runtime fact. For `HYPOTHESIS`, first establish missing static evidence. If required source or configuration is unavailable, defer as `NEEDS_CONTEXT`; do not repeatedly execute clearly falsified candidates without new evidence.

Before validation, set per-candidate time and attempt budgets, guest CPU/memory/process limits, and stopping criteria for lack of progress. If the user provides no limits, choose and record finite values appropriate to the complexity. Do not solve long races or reference-count wraparound conditions by exhausting host resources.

## 2. Isolation and Target Matching

Run PoCs and reproduction workloads only in task-owned VMs or official services authorized for the specific action and destination. Containers share the host kernel and do not qualify as isolation for this purpose.

- Before creating a VM, check collisions including stopped directories, and use `<task>_<unix-timestamp>`. Record profile, name, path, creation time, and owning worker.
- Check the current CLI of the reviewed `tools/vm.sh` and `tools/kernel.sh`. Specify profiles with `-p` and VMs with `-p <profile> -v <vm>` before the subcommand; place `--` before SSH remote commands.
- Transfer files using `tools/vm.sh ... scp` and `vm:` guest paths. Do not attach host shared directories. If no existing image is available, record the preparation requirement. Do not run host-mounting `fs.sh create` or `create-image.sh`.
- Do not modify the host kernel, sysctl settings, modules, or services. Do not stop or reset another owner's VM. Restrict crash recovery to recorded task-owned VMs.

In `environment.md`, record the source commit and local changes, hashes of the kernel image/vmlinux/configuration, compiler and build commands, boot arguments, guest image, architecture, CPU/memory, and actually booted kernel. Do not claim an exact image match from a `uname` string alone.

Choose diagnostics appropriate to the hypothesis, such as KASAN for memory errors or KCSAN for suspected races. Verify actual configuration and activation; identify diagnostic changes from the target configuration. Record instrumentation, inserted delays, and fault injection as separate experimental conditions. Experiments that alter logic to create a defect are not reproduction evidence for the original candidate.

For KernelCTF, check current official rules, target images, and starting privileges through read-only access, and record eligibility separately. If remote execution is authorized, read [kctf-official-helper](../kctf-official-helper/SKILL.md). Certificates or connection tools do not imply permission for official attempts, uploads, or submissions; do not request authorization already granted.

If KernelCTF rules require an LTS crash through `--vuln-trigger` separately from hardened-target exploitation, record LTS reproduction as a separate experiment in this stage. Preserve exact release, configuration, and hashes per target; distinguish KASAN-only crashes from uninstrumented LTS crashes. Success on one target does not substitute for success on another.

## 3. Minimal Reproducer and Evidence-Based Iteration

1. Write a readable reproducer containing only operations needed from the attacker entry point to the faulty operation. Record syscall return values and errno, progress stages, inputs, and seeds to distinguish reachability failures.
2. Preserve compilation commands and source/binary hashes. Even when building on the host, run execution and smoke tests only in the guest.
3. Separate administrator preparation from attacker actions. Record runtime UID/GID, capabilities, namespaces, and file/device access permissions. Do not label execution from a root SSH session as unprivileged reproduction.
4. Start guest console capture and set time limits before execution. Preserve stdout/stderr, exit codes, kernel logs, and original console output in per-attempt paths. Secure console evidence in case SSH disconnects.
5. On failure, compare the last reached stage with the expected path. Distinguish rejected input, missing configuration, insufficient privileges, ordering/timing issues, missing instrumentation, and infrastructure failure.
6. Apply only changes supported by new observations. Record each attempt's change rationale, inputs, environment differences, and result; do not overwrite success or failure logs.

Absence of a KASAN report alone does not establish safety. Check diagnostic coverage, path reachability, attempt counts, and missed observations. A KCSAN report is evidence of a data race, not by itself proof of memory corruption or security impact. For non-memory defects, use concrete observation criteria comparing expected and actual state.

## 4. Causality and Minimization

When a crash occurs, secure original evidence before repeating execution.

- Decode stacks using symbols from that build, and connect the first error location, access type/size, object lifetime, and allocation/free stacks to the candidate's source path.
- Explain the chain from input → state transition → invariant violation → runtime observation. Do not infer root cause solely from a secondary crash after corruption or a one-line sanitizer summary.
- If a different bug triggers, record it separately and do not count it as success for the original candidate.
- Separate infrastructure failures such as QEMU, SSH, watchdog, OOM, or incorrect images from the kernel candidate. Do not expand the investigation to the host or isolation boundary.
- Remove unnecessary calls, inputs, and threads, then retry the final reproducer from a clean guest state. Record execution order, concurrency, seed, elapsed time, and successes/total attempts.
- Where possible, run a control with the key trigger condition removed. Its absence in the control does not alone establish causality; also use source and stack evidence.

If confirmation requires added instrumentation or privileges, retain those conditions in the verdict's scope. Reachability and reproduction in the actual target environment are separate dimensions. If minimization loses reproduction, preserve the last successful version too.

## Verdict Criteria

Preserve the static-stage status and assign a separate `Validation-status`.

| Status | Criteria |
|---|---|
| `DYNAMIC_CONFIRMED` | The defect was observed in the specified environment, linked to the designated root cause, and supported by original evidence and reproduction steps. |
| `OBSERVED_UNATTRIBUTED` | Abnormal behavior was observed, but causality with the designated candidate was not established. |
| `NOT_REPRODUCED` | Not reproduced within the recorded conditions and attempt budget; this does not mean falsification. |
| `REJECTED` | Concrete evidence falsifies the candidate, such as impossible prerequisites or an actual defense. |
| `NEEDS_CONTEXT` | Required source, configuration, environment, or privilege information is missing. |
| `INFRA_BLOCKED` | Image, boot, tooling, or resource problems prevented a valid experiment. |

Limit `DYNAMIC_CONFIRMED` to the demonstrated environment. A single occurrence may be recorded if original evidence and causality suffice, but state repeatability limitations. Do not claim that a crash or sanitizer report proves LPE, arbitrary read/write, official-target eligibility, or flag acquisition.

## Completion and Handoff

Stop execution for a candidate when reproduction and causality are established, the candidate is falsified, execution or no-progress limits are reached, or required infrastructure is absent. Do not extend unproductive repetition indefinitely. Continue with remaining independent candidates; record stopping reasons and follow-up experiments.

Include only needed files in the candidate directory, but make the following reconstructable:

```text
environment.md       Target, configuration, privileges, VM ownership, diagnostic conditions
repro/               Final reproducer, build/run procedures, required inputs
attempts/<run-id>/   Commands, inputs, outputs, original console/kernel logs, stopping reasons
validation.md        Causal analysis, verdict, repeatability, limitations, next steps
SHA256SUMS           Hashes of handed-off source, binaries, configurations, and evidence
```

Include Candidate-ID, Target-ID, original static-record path, Validation-status, actual observations, source connections, reachable privileges, target/experiment differences, successes/total attempts, important failures, unverified impacts, and evidence paths in `validation.md`. Preserve enough failed attempts to understand the bounds of non-reproduction.

Before completion, merge confirmed facts, useful primitives, important negative results, unresolved issues, and evidence paths/hashes into existing `agent/<research-name>/FINDINGS.md`. Hand these materials to exploitability assessment or patching; proceed only when that stage is authorized.

## Design Rationale

Adapted from dynamic validation in OpenAI's [A thousand fewer paths to root](https://openai.com/ko-KR/index/a-thousand-fewer-paths-to-root/): minimal reproducers in isolation, iteration using execution evidence, and separating static candidates from validated results. The statuses and file structure above are operational choices tailored to this repository's handoff and isolation rules, not a reproduction of undisclosed internal implementation details.
