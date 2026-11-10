---
name: patch-generation
description: Fix root causes of dynamically confirmed Linux kernel vulnerabilities with minimal changes, and validate patch correctness and completeness through local coding conventions, static checks, builds, reproducer regression, and variant/bypass analysis. Use for security patch creation and review; vulnerability discovery, exploit development, and upstream submission are separate stages.
---

# Patch Generation

Produce reviewable patch candidates that fix the root cause of each validated vulnerability. Restore the violated invariant rather than merely silencing one reproducer, while meeting functional, performance, compatibility, and concurrency requirements and surrounding development conventions.

## Scope and Entry Gate

- First read `AGENTS.md`, the static candidate, `validation.md`, and, when needed, `exploitability.md` and the independent causal review. Handle only Candidate-IDs/Target-IDs authorized for patch generation.
- Minimum inputs are the exact vulnerable revision/configuration, `DYNAMIC_CONFIRMED` evidence, minimal reproducer and original logs, and violated invariant. A working exploit is not required; failed exploitation is not a reason to defer patching.
- Assign generation and validation to `kernel_astra`/`gpt-6-astra`; record the actual role/model. If unsupported, suspend this stage rather than misrepresenting results from another model.
- Source inspection, edits, static checks, and builds may run on the host. Run reproducers, exploits, and regression workloads affecting the kernel only in task-owned VMs. Do not overwrite user changes in existing source trees.
- Store artifacts in `agent/<research-name>/patch/<candidate-id>/`. Do not make unrequested commits or pushes in the original kernel source. Do not submit externally, contact third parties, or disclose.

## 1. Recheck the Latest Target

Fix the baseline before writing a patch.

1. Distinguish the handed-off vulnerable revision from the latest revision under review.
2. Check current code and public history for merged or pending fixes, duplicates sharing the root cause, and related refactoring.
3. Verify that the entry path, violated invariant, and reproducibility remain in current code.
4. If already correctly fixed, record `ALREADY_FIXED` with the supporting commit and scope instead of creating a new patch.

Do not present a candidate absent from current code as a new zero-day patch for a historical revision. If scope covers a backport needed only for the handed-off revision, state its differences from the upstream fix.

## 2. Fix Design

First write the following in `patch-analysis.md`:

```text
Candidate-ID / Target-ID:
Base revision and config:
Root cause and violated invariant:
First invalid operation:
All known entry/cleanup/concurrent paths:
Required functional behavior:
Non-functional constraints: locking, allocation context, ABI, performance, compatibility
Existing local idioms/helpers:
Alternative fixes and rejected tradeoffs:
Chosen invariant-restoring change:
```

Read surrounding files and the subsystem's success/error paths, locking rules, reference-count conventions, helpers, coding style, and tests. Prioritize these principles:

- Validate attacker inputs or state at the earliest boundary that permits the defect.
- Restore object lifetime, ownership, locking, and length invariants symmetrically across all paths.
- Avoid unnecessary abstractions, broad refactoring, ABI changes, and hot-path costs.
- Do not cover memory-safety defects merely with `WARN`, crashes, disabling functionality, or blocking reproducer patterns.
- Preserve error codes, cleanup order, lock ordering, allocation flags, and context constraints.

## 3. Patch Writing and Static Review

Create the minimum diff needed for one root cause and preserve it as `fix.patch`. Use only verified facts in the proposed explanation to connect symptoms, root cause, restored invariant, and validation results. Do not invent unverified CVEs, severity, `Fixes:` tags, or reporter information.

At minimum, check:

- Does the invariant hold across all changed success, error, cancellation, release, retry, and asynchronous paths?
- Are there new problems in lock scope, race windows, reference acquisition/release, integer conversions, or usercopy boundaries?
- Do all callers handle new return values or states?
- Are definitions and behavior consistent across configuration-dependent `#ifdef` branches, stubs, and architecture-specific paths?
- Does the change follow local style, helpers, and kernel conventions without unnecessary comments or duplicate code?

Run `git diff --check`, relevant compiler diagnostics, and subsystem static-check tools where possible. Interpret warnings against current source; do not record unperformed checks as passing.

## 4. Variant and Attacker-Perspective Review

Search code sharing the same invariant, beyond the immediate reproduction path.

- Other callers of the same helpers, structures, state machines, or allocation/free patterns
- Error handling, cancellation, timeout, teardown, duplicate requests, and cross-thread paths
- Other combinations of lengths, types, and flags; compat syscalls; architecture and configuration variants
- Alternative entry points bypassing checks before the patch, or TOCTOU state changes after checks
- Whether the fix blocks only one variant while leaving the same root cause elsewhere

Classify each item in `variants.md` as `FIXED_BY_PATCH`, `NOT_AFFECTED`, `SEPARATE_CANDIDATE`, or `UNRESOLVED`, with source evidence. Hand separate root causes off as new candidates instead of inflating the current patch. If a working exploit exists, have an independent worker other than its developer review bypass possibilities, without unlimited expansion into new attack-surface discovery.

## 5. Builds and Dynamic Regression

Specify before/after comparisons and functional regression in `test-plan.md` before executing.

1. Verify that the original reproducer produces expected evidence on the exact base.
2. Verify that `fix.patch` applies cleanly to pristine source.
3. Build with the target configuration and necessary representative configurations; verify the modified subsystem is actually included.
4. Run the same reproducer in a task-owned VM with the same privileges, inputs, and attempt conditions to check that the defect disappears.
5. Check functional regression with normal and boundary inputs, error/cancellation paths, and relevant existing tests.
6. If an exploit exists, rerun it on the patched kernel with the same target mitigations.
7. Check for new sanitizer, lockdep, refcount, leak, performance, or timeout anomalies.

Do not claim completion merely because the reproducer no longer crashes. Verify in source and at runtime that the patched path actually executes, completes normally, and removes the cause. Without build or experiment infrastructure, leave the result `UNVALIDATED`; do not infer outcomes.

## Verdicts and Artifacts

| Status | Criteria |
|---|---|
| `PATCH_VALIDATED` | A minimal fix removes the root cause and passes build, reproducer regression, functional regression, and variant review. |
| `PATCH_PARTIAL` | Some paths are fixed, but variants, configurations, or regressions remain unresolved. |
| `PATCH_UNVALIDATED` | A candidate patch exists, but required builds or dynamic validation are incomplete. |
| `ALREADY_FIXED` | An existing fix in the latest target and its scope have been verified. |
| `RETURN_TO_ANALYSIS` | Insufficient root-cause or causal evidence prevents defining a safe fix scope. |
| `INFRA_BLOCKED` | Build/VM infrastructure problems prevented valid validation. |

```text
patch-analysis.md       Root cause, requirements, alternatives, selection rationale
fix.patch               Minimal patch applying to the exact base
commit-message.txt      Proposed explanation containing only confirmed facts
variants.md             Related paths, bypasses, and variant analysis
test-plan.md            Before/after comparisons and regression plan
build/                  Commands, configurations/tool versions, result logs
tests/<run-id>/         Original reproduction/normal/boundary/exploit evidence
patch-review.md         Final verdict, remaining risks, applicability
SHA256SUMS              Handoff file hashes
```

Merge patch status, base revision, restored invariant, test results, variants, remaining risks, and evidence paths/hashes into `FINDINGS.md`. Hand off applicability criteria, failure logs, and unvalidated scope along with the patch to `human-report`.

## Design Rationale

Reflects patch generation with full relevant source, adherence to local development conventions, static checks, minimal changes, variant/bypass analysis, and iterative improvement in OpenAI's [A thousand fewer paths to root](https://openai.com/ko-KR/index/a-thousand-fewer-paths-to-root/). Both functional and non-functional requirements are gates to distinguish a reviewable security patch from a functional fix that merely passes the reproducer.
