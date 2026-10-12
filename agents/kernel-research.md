# Kernel vulnerability research: shared contract

Read this entry point before any kernel vulnerability discovery, triage,
reproduction, exploitability analysis, or exploit development. The stage rules
are cumulative:

| Requested work | Additional required documents |
| --- | --- |
| Discovery, source audit, or static triage | [`kernel-discovery.md`](kernel-discovery.md) |
| Existing report, patch, or suspicious-path triage | [`kernel-discovery.md`](kernel-discovery.md); add [`kernel-reproduction.md`](kernel-reproduction.md) before runtime validation |
| Reproduction, runtime crash triage, or dynamic confirmation | [`kernel-discovery.md`](kernel-discovery.md), then [`kernel-reproduction.md`](kernel-reproduction.md) |
| Exploitability or exploit development | [`kernel-discovery.md`](kernel-discovery.md), [`kernel-reproduction.md`](kernel-reproduction.md), then [`kernel-exploitation.md`](kernel-exploitation.md) |

Also follow [`vm-operations.md`](vm-operations.md) for any VM, build, guest,
transfer, or debugging operation; [`kernelctf-submission.md`](kernelctf-submission.md)
for KernelCTF work; and [`reporting-and-cleanup.md`](reporting-and-cleanup.md) for
final reporting, preservation, termination, or cleanup. If the requested mode
changes, read the newly applicable document before acting.

## Core discipline

Optimize for validated findings, not files read, warnings produced, or candidates
listed. Models increase coverage over known bug patterns; they do not establish
novelty, reachability, impact, or correctness. Use a repeatable
**select → hypothesize → falsify → test → record → iterate** loop.

Keep observed facts, source-supported deductions, unverified assumptions, and
hypotheses distinct. Verify every cited path, symbol, line, commit, config value,
command flag, and diagnostic against the current target. Actively search for the
lock, reference, validation, serialization, or teardown guarantee that would
disprove a candidate.

## Select the mode and target

Choose the least invasive mode that satisfies the request:

- **Discovery:** find and validate source-level candidates; stop before
  exploitability work or exploit development unless requested.
- **Triage:** assess an existing report, crash, patch, or suspicious path.
- **Reproduction:** build a minimal instrumented trigger and measure it.
- **Exploitability:** determine realistic primitives and blockers without
  assuming a complete chain.
- **Exploit development:** proceed only when expressly requested and the earlier
  gates pass.

Before analysis, record the exact source provenance and commit, architecture,
build and `.config`, boot parameters, hardening, KASAN/KCSAN state, sysctls,
modules, image and profile identity, UID/GID and effective credential state,
capabilities, namespaces, LSM/seccomp restrictions, permitted syscalls, and
reachable interfaces. Never record secret credential material. Mark a missing
critical fact `UNKNOWN` and resolve it before claiming reachability or impact.

Initialize this task-owned research state before creating candidates:

```text
$SHARE/<research-name>/
├── README.md
├── MANIFEST.md
├── FINDINGS.md
├── candidates.md
├── coverage.md
├── Makefile
├── src/
├── logs/
└── artifacts/
```

Use one stable research name for its share directory, VM ownership records, and
reports. `MANIFEST.md` records the task, profile and VM names, creation time,
kernel commit and image hash, config hash, toolchain, launch options, commands,
and artifact SHA-256 values. Never overwrite another task's records; use a
task-specific subdirectory or distinct research name when ownership differs.

## Shared evidence model

Every candidate goes into `candidates.md` using this minimum schema:

| Field | Required content |
| --- | --- |
| ID and root-cause status | Stable ID and one allowed status below |
| Location | Verified file, function, line/commit, and call path |
| Claim | Exact invariant and invalid state transition or interleaving |
| Reachability | Entry point, config, credentials, privileges, and minimal steps |
| Target reachability | `VERIFIED`, `UNVERIFIED`, or `UNREACHABLE`, with evidence |
| Exploitability | `OBSERVED`, `PLAUSIBLE`, `UNKNOWN`, or `NONE`, with evidence |
| Evidence | Source excerpts, definitions, traces, or diagnostics that exist |
| Counterevidence | Guards, locks, references, or benign explanations |
| Falsifier | Cheapest concrete check that could disprove the claim |
| Expected observation | Specific state, stack, access, or diagnostic predicted |

Allowed root-cause statuses are:

- `WEAK_HYPOTHESIS`: plausible concern with major source assumptions unresolved.
- `STRONG_HYPOTHESIS`: a concrete violation is supported by source, but the proof
  is incomplete or depends on unresolved conditions.
- `SOURCE_CONFIRMED`: exact inputs, arithmetic, control flow, or interleaving
  establish the invariant violation from source evidence. This does not imply
  that the path is compiled, target reachability, dynamic reproducibility, or
  exploitability.
- `DYNAMIC_CONFIRMED`: runtime evidence reproduces the predicted invalid state or
  diagnostic and matches the source-level root cause.
- `REFUTED`: a necessary condition or claimed invariant violation is false.
- `BLOCKED`: the source claim cannot currently be resolved because a required
  revision, definition, artifact, or analysis input is unavailable.

Root-cause status, target reachability, and exploitability are independent axes.
Never downgrade a valid source proof merely because the target path is
unreachable, and never promote reachability or impact from `SOURCE_CONFIRMED`
alone. Do not use arbitrary numeric confidence scores.

## Progress and handoff

At each handoff, update `coverage.md`, `candidates.md`, `MANIFEST.md`, and
`FINDINGS.md`. Report:

- `SOURCE_CONFIRMED` and `DYNAMIC_CONFIRMED` findings separately, with target
  reachability and exploitability evidence;
- the strongest unconfirmed candidate, its main counterargument, and cheapest
  next test;
- refuted and blocked candidates with specific reasons; and
- experiments actually executed, ledger changes, and remaining constraints.

Never let polished model prose substitute for evidence or overstate severity.
If no root cause reaches `SOURCE_CONFIRMED` or `DYNAMIC_CONFIRMED`, state “No
confirmed root cause in the investigated scope,” not that the subsystem is safe.
If a source-confirmed bug is not verified on the target, say so rather than
calling it a target vulnerability. End or switch scope when remaining experiments
are redundant, necessary assumptions are disproved, no evidence-backed next step
remains within budget, or the requested mode is complete.
