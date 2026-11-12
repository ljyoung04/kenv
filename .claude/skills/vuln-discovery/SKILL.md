---
name: vuln-discovery
description: Statically audit a kernel source tree for vulnerability candidates in kenv. Selects audit targets by low-privilege reachability and security relevance, then analyzes and actively falsifies hypotheses. Use for source audits, vulnerability discovery, and static triage; not for running PoCs, dynamic validation, or patching.
---

# Vulnerability Discovery

Narrow a large codebase in two passes, then deliver a small set of candidates
with verifiable static evidence and preserved negative results.

1. **Scout pass** — read broadly and shallowly; pick surfaces worth a deep audit.
2. **Analyst pass** — read each surface deeply, form hypotheses, and try to
   falsify them.

The goal is fewer, better candidates, not a large count. Scanner warnings,
suspicious-looking code, and model explanations are leads, not findings.

## Scope

- Follow root `AGENTS.md` (isolation, VM naming, artifact locations).
- **Static only.** Source reading, `git log`/`git blame`, `rg`, compiler
  diagnostics, static analyzers, and public documentation may run on the host.
- Do not build-and-run PoCs, fuzz, boot VMs, or write patches in this stage.
  Those belong to `dynamic-validation` and `patch-generation`.
- Read public rules, source, and patches read-only. Do not contact third
  parties, upload, submit, or disclose.
- Write everything under `agent/<research-name>/`.

## Execution model

Run both passes yourself by default. Use subagents only when the user asks
for them. If they do:

- Give scouts non-overlapping directories, subsystems, or interfaces.
- Give each analyst exclusive ownership of specific Target-IDs.
- Hand analysts the structured target record below, not a scout's bug
  speculation, so analysis is not anchored on it.
- Only the orchestrator writes `targets.md` and `FINDINGS.md`.

## 0. Scope record

Write `agent/<research-name>/scope.md` before auditing:

- Source tree path and exact revision (`git rev-parse HEAD`, or the release tag
  plus local diff hash when not a git checkout)
- Exact config file and its SHA-256 (for example `configs/kernelctf.config`),
  and whether `KOBJ/.config` matches it after `olddefconfig`
- Audit scope and explicit exclusions
- Threat model: attacker start (UID/GID, capabilities, namespaces available),
  trust boundary, expected impact class
- Budget: time or target count, and the stopping condition

Label assumptions that could change a verdict. If the revision cannot be
pinned, mark all results provisional.

### Config is ground truth

Decide reachability from the actual config, not from the source tree.
For each surface, confirm that the controlling `CONFIG_*` options are set in
the target `.config` and that the file is actually compiled (`obj-$(CONFIG_X)`
in the Makefile). Prefer a generated `compile_commands.json`
(`kernel.sh -p <p> --clang`) or the built object list when a build exists.

### KernelCTF eligibility (when the target is kernelCTF)

Check the current [rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md)
read-only at the start. Rules change; never rely on memory or old configs.
Record the URL and lookup time in `scope.md`, then track separately:

| Field | Question |
|---|---|
| `Freshness` | No mainline fix, and no disallowed prior disclosure? |
| `Duplicate` | No existing submission or public report with the same root cause or fix? |
| `Target-build` | Code and attack surface compiled into the current target config? |
| `LTS-trigger` | Is the same root cause triggerable on the required LTS target? |
| `Attacker` | Reachable under the official starting privileges and disabled subsystems? |

Leave anything public information cannot resolve as `UNKNOWN`. Do not use
the official service here; that requires `kctf-official-helper` and explicit
user approval.

## 1. Scout pass

Judge each surface on two **separate** axes. Do not merge them into one score.

**Reachability**
- Concrete entry from low privilege: syscall, file op, ioctl, socket/protocol,
  netlink, io_uring op, parser, callback, workqueue/timer, RCU callback
- Prerequisites: capabilities, user namespaces, devices, mounts, network
  state, sysctls

**Security relevance**
- Parses or copies data across a trust boundary
- Manages lifetimes, refcounts, shared state, credentials, sizes, or indices
- Has complex error unwinding, async teardown, lock hand-offs, type
  conversions, or variable-length data

File size or "it's C" is not a reason to select code. A small adapter that
carries attacker input across a lifetime or privilege boundary is.

Write `agent/<research-name>/exploration/<scope-id>.md`, one record per target:

```text
Target-ID: T-0001
Owner-scope: <assigned area>
Code: <files, directories, key symbols>
Entry: <attacker-originated entry point>
Config-gates: <CONFIG_* required; set in target .config? y/n>
Reachability: high | medium | low | unknown
Security-relevance: high | medium | low
Boundary: <trust / privilege / lifetime boundary>
Attacker-control: <controllable values and constraints>
Preconditions: <privileges, namespaces, state>
Dependencies: <callers, callees, structures to read together>
Why-audit: <concrete reason>
Why-not: <reason for lower priority or exclusion>
```

If a bug idea comes up while scouting, write one or two sentences and move on.
Do not start deep analysis here.

## 2. Scout → analyst gate

Consolidate into `agent/<research-name>/targets.md`:

1. Merge surfaces that share an entry point, object lifetime, or root cause.
2. Drop or deprioritize surfaces unreachable under the threat model or config.
3. Split oversized units at call or lifetime boundaries; merge undersized
   units with the code needed to understand their invariants.
4. Record every include/exclude decision with evidence, so unaudited areas
   stay visible as coverage gaps.

Prioritize by reachability × security relevance × attacker control. Keep
`unknown` reachability targets when resolving the unknown is cheap.

## 3. Analyst pass

Follow `Dependencies` and real call edges to where each invariant is
established and where it ends. Explain the normal behavior first.

1. Trace concrete call and data flow from attacker input to the sensitive
   operation.
2. Write down the invariants: ownership, refcount, length, type, lock, state
   machine, permission check.
3. Compare the normal path with error, cancel, retry, release, async callback,
   and cross-thread paths. Most real kernel bugs live in teardown and
   concurrent paths.
4. Consider lifetime errors, bounds and integer errors, races, uninitialized
   memory, info leaks, type confusion, missing permission checks, and TOCTOU,
   guided by what the code actually does. This is not a checklist to
   pattern-match.
5. Apply the falsification below. Keep only the survivors.

### Required falsification

Answer each question for every hypothesis:

- Is the entry compiled and reachable in this revision and config?
- Does earlier validation, a length cap, a permission check, a reference
  grab, a lock, or serialization (RCU, `SLAB_TYPESAFE_BY_RCU`, a workqueue
  flush) block the path?
- Do the assumptions about error, release, and callback ordering hold on
  every relevant path?
- Can the attacker actually control the required values, timing, and state?
- Do compiler, language, or runtime guarantees remove the suspected behavior?
- Is it already fixed upstream or in a stable branch? Check `git log -S`/`-G`
  on the symbols, and mainline/stable history newer than the target.
- Does the outcome cross a security boundary, or is it a functional bug or a
  self-only failure?

Keep falsified hypotheses with the reason and the evidence location. If
missing code or config prevents a decision, use `NEEDS_CONTEXT`. Do not fill
the gap with guesses.

### Candidate record

Write `agent/<research-name>/analysis/<target-id>.md`. Keep investigated
paths and negative results even when nothing survives.

```text
Candidate-ID: C-0001
Target-ID: T-0001
Status: HYPOTHESIS | SOURCE_CONFIRMED | REJECTED | NEEDS_CONTEXT
Revision/config: <exact tree, commit, config hash>
Class: <defect type>
Root cause: <one sentence>
Fix locus: <where a correct fix would go; used for dedup>
Entry path: <symbol chain from attacker input to defect>
Attacker control: <values, objects, timing, constraints>
Preconditions: <privileges, namespaces, config, state>
Violated invariant: <expected invariant and how it breaks>
Source evidence: <file:line, symbols, branches>
Primitive: <what the defect statically gives, e.g. UAF write of N bytes in kmalloc-192>
Impact hypothesis: <consequence needing runtime or human confirmation>
Falsification: <defenses checked, attempts, results>
Counterevidence/unknowns: <adverse evidence, unverified points>
Duplicate/fix check: <commands run, commits found>
Next validation: <minimal trigger idea, diagnostics needed (KASAN/KCSAN/...), expected first bad access; do not execute>
KernelCTF-eligibility: ELIGIBLE_CANDIDATE | INELIGIBLE | UNKNOWN | NOT_APPLICABLE
Eligibility evidence: <rules URL/time, target and LTS inclusion, unknowns>
```

`SOURCE_CONFIRMED` means the call/data flow and the invariant violation were
read directly in current source under the listed preconditions. It does not
mean the bug reproduces or that impact is confirmed. This skill never assigns
`DYNAMIC_CONFIRMED`.

## 4. Quality gate and dedup

Before handing off, check that:

- Files, symbols, line numbers, config options, and call paths match the
  pinned revision.
- No step is missing between the root cause and the claimed primitive.
- **Candidates are deduplicated by fix, not by symptom.** Two entry points
  that a single patch would close are one root cause. One entry point that
  needs two independent patches is two candidates.
- Reachability, static confidence, potential impact, and validation cost are
  recorded separately.
- Severity wording does not go beyond the static evidence.

For an especially important or disputed candidate, do an independent re-read.
Start from the original code and threat model, not from the earlier
conclusion, and check whether the same causal chain holds.

## 5. Completion

Static discovery is complete when:

- All assigned scope is classified as audited, excluded, or unreviewed.
- Every selected target is analyzed or has a concrete stopping reason.
- Every candidate has a status, evidence, falsification results,
  preconditions, and a next validation step.

Update `agent/<research-name>/FINDINGS.md` with:

- Revision, config hash, threat model
- Coverage: audited, excluded, and unreviewed areas
- Prioritized `SOURCE_CONFIRMED` and `HYPOTHESIS` candidates
- Important `REJECTED` results, to prevent redundant re-exploration
- `NEEDS_CONTEXT` items and the inputs they need
- Evidence paths and SHA-256 for the next stage

If nothing survives, do not write "no vulnerabilities." Write that no
candidate was confirmed within the audited scope, the threat model, and the
listed blind spots.

## Background

Modeled on the Scout → Analyst stages of OpenAI's
[A thousand fewer paths to root](https://openai.com/index/a-thousand-fewer-paths-to-root/):
pick low-privilege-reachable targets first, then audit each one deeply, and
count distinct bugs by the separate patch each needs. The record formats and
gates here are this repository's own choices.
