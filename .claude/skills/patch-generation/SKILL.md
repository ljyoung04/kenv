---
name: patch-generation
description: Write a minimal root-cause fix for a dynamically confirmed Linux kernel vulnerability, then validate it with kernel conventions (checkpatch), builds, reproducer regression, functional regression, and variant analysis. Use for security patch creation and review; discovery, validation, and upstream submission are separate stages.
---

# Patch Generation

Produce a reviewable patch per root cause. Restore the violated invariant;
do not just silence one reproducer. Meet functional, performance,
compatibility, and concurrency requirements, and the subsystem's own
conventions.

## Scope and entry gate

- Read root `AGENTS.md`, the candidate record, `validation.md`, the
  reproducer, and the original logs.
- Required inputs: exact vulnerable revision and config, `DYNAMIC_CONFIRMED`
  evidence, the minimal reproducer, and the violated invariant. If any are
  missing, return `RETURN_TO_ANALYSIS`.
- Check inherited evidence instead of trusting its summary. Re-hash the
  logs, read the sanitizer report yourself, and confirm that it matches the
  candidate's first invalid operation, as `validation.md` claims. On a
  mismatch, return `RETURN_TO_ANALYSIS`.
- Editing, static checks, and builds may run on the host. Reproducers and
  regression workloads run only in task-owned VMs.
- **Do not edit the shared source tree in place.** Use a `git worktree` or a
  copy under `kernels/` (for example `kernels/<tree>-fix-<candidate>`) with its
  own profile and `KOBJ`. Do not commit to or push the original tree.
- Write artifacts to `agent/<research-name>/patch/<candidate-id>/`. Do not
  send email, open PRs, or contact maintainers.

## 1. Re-check against the latest code

1. Separate the vulnerable revision you were handed from the latest
   upstream you are reviewing.
2. Search upstream and stable history and public lists for an existing or
   pending fix, duplicates with the same root cause, and related refactors.
3. Confirm that the entry path and the invariant violation still exist in
   current code.
4. If it is already fixed correctly, record `ALREADY_FIXED` with the commit
   and its scope instead of writing a new patch.

If the bug exists only in an older revision, label any patch a backport and
state how it differs from the upstream fix.

## 2. Design

Write `patch-analysis.md` first:

```text
Candidate-ID / Target-ID:
Base revision and config:
Root cause and violated invariant:
First invalid operation:
All known entry / cleanup / concurrent paths:
Required functional behavior:
Constraints: locking, allocation context (GFP, atomic), ABI, hot paths, stable backportability
Local idioms and helpers to reuse:
Alternatives considered and why rejected:
Chosen change:
Introducing commit: <from git blame / log -S; verified or UNKNOWN>
```

Read the surrounding subsystem: its success and error paths, lock rules,
refcount conventions, helpers, style, and existing selftests. Principles:

- Validate attacker input or state at the earliest boundary that allows the
  defect.
- Restore lifetime, ownership, locking, and length invariants symmetrically
  on all paths.
- Avoid new abstractions, broad refactors, ABI changes, and hot-path cost.
  A known weakness of AI-written patches is adding unnecessary code.
- Do not paper over memory-safety bugs with `WARN`, by disabling the
  feature, or by blocking the reproducer's specific pattern.
- Keep error codes, cleanup order, lock order, GFP flags, and context
  constraints intact.

## 3. Write and review the patch

Create the smallest diff that fixes one root cause, and save it as
`fix.patch` (`git format-patch` style). In `commit-message.txt`, follow kernel
format: subsystem prefix in the subject, then root cause, how it is
triggered, and why the fix is correct, using only verified facts.

- Add `Fixes: <12-char sha> ("subject")` only when the introducing commit is
  verified with blame or log. Otherwise leave it out and note `UNKNOWN`.
- Do not invent CVE IDs, reporter tags, or severity.
- Record suggested recipients from `scripts/get_maintainer.pl fix.patch`
  for the human reviewer. Do not send anything.

Self-review:

- Does the invariant hold on every success, error, cancel, release, retry,
  and async path that changed?
- Are there new problems with lock scope, race windows, reference
  grab/drop, integer conversions, or usercopy bounds?
- Do all callers handle any new return value or state?
- Are `#ifdef` branches, stubs, compat paths, and arch variants consistent?

Run `scripts/checkpatch.pl --strict fix.patch`, `git diff --check`, and the
build with `W=1` for touched files. Run sparse (`C=1`) or smatch if they are
available. Never record a check you did not run as passed.

## 4. Variants and completeness

Search beyond the reproduced path for code that shares the same invariant:

- Other users of the same helper, structure, state machine, or alloc/free
  pattern
- Error, cancel, timeout, teardown, duplicate-request, and cross-thread paths
- Other length, type, and flag combinations; compat syscalls; arch and
  config variants
- Alternate entry points that skip the check, or TOCTOU changes after it

Classify each item in `variants.md` as `FIXED_BY_PATCH`, `NOT_AFFECTED`,
`SEPARATE_CANDIDATE`, or `UNRESOLVED`, with source evidence.

**One patch, one bug.** If one patch closes several candidates, they are one
root cause; merge their records. If a variant needs its own independent
fix, hand it back as a new candidate instead of inflating this patch.

For a high-risk completeness question, re-review it from the original code
rather than from your chosen fix, so you are not anchored on it.

## 5. Build and regression

Write `test-plan.md` before running anything.

1. Confirm that the original reproducer still reproduces on the exact
   unpatched base.
2. Confirm that `fix.patch` applies cleanly (`git apply --check`) to a
   pristine base.
3. Build the target config and the sanitizer config. Confirm the changed
   files are actually compiled.
4. Run the same reproducer, with the same privileges, inputs, and attempt
   count, in a fresh task-owned VM on the patched kernel. The defect must
   be gone.
5. Check functional regression: normal and boundary inputs, error and
   cancel paths, and relevant `tools/testing/selftests` targets or LTP.
6. Check for new sanitizer, lockdep, refcount, leak, or timeout reports.

"No crash" is not enough. Show, through source and runtime evidence (a
progress marker, ftrace, or a new error code), that the patched path ran
and handled the case. Without infrastructure, the status is
`PATCH_UNVALIDATED`; do not infer results.

## Verdicts and artifacts

| Status | Criteria |
|---|---|
| `PATCH_VALIDATED` | Minimal fix removes the root cause; passes build, reproducer regression, functional regression, and variant review |
| `PATCH_PARTIAL` | Some paths fixed; variants, configs, or regressions still open |
| `PATCH_UNVALIDATED` | Patch exists; required builds or dynamic checks are incomplete |
| `ALREADY_FIXED` | An existing upstream fix and its scope were verified |
| `RETURN_TO_ANALYSIS` | Not enough root-cause evidence to define a safe fix |
| `INFRA_BLOCKED` | Build or VM problems prevented validation |

```text
patch/<candidate-id>/
  patch-analysis.md
  fix.patch
  commit-message.txt
  variants.md
  test-plan.md
  build/            commands, config, toolchain versions, logs, checkpatch output
  tests/<run-id>/   before/after reproducer, functional and boundary evidence
  patch-review.md   verdict, remaining risks, applicability, suggested recipients
  SHA256SUMS
```

Merge the results into `FINDINGS.md`. Hand them to `human-report` together
with failure logs and the unvalidated scope.

## Background

Reflects the patch stage of OpenAI's
[A thousand fewer paths to root](https://openai.com/index/a-thousand-fewer-paths-to-root/):
write one candidate patch per issue, group findings by the separate patch
each needs, and check for the weaknesses the post reports in early AI
patches (unnecessary code, performance cost, ignored kernel conventions,
missed variants). Every patch still needs human and maintainer review.
