---
name: vuln-discovery
description: Select audit targets in large codebases by low-privilege reachability and security relevance, then orchestrate separate analysis agents to find and falsify vulnerability candidates statically. Use for source audits, vulnerability discovery, and static triage, not PoC execution, dynamic validation, exploit development, or patching.
---

# Vulnerability Discovery

For KernelCTF, prioritize candidates consistent with current official rules. Rules and targets can change; do not establish eligibility from memory or historical configurations alone.

Narrow a large codebase through two simple agent passes.

1. **Exploration agents** read broadly and shallowly to identify surfaces worth auditing.
2. **Analysis agents** deeply inspect handed-off surfaces, form vulnerability hypotheses, and actively attempt to falsify them.

Deliver candidates with verifiable static evidence and important negative results. Increasing candidate counts is not the goal. Scanner warnings, suspicious code, and model explanations are not vulnerabilities by themselves.

Only when public rules and release information are insufficient and the user has authorized the exact remote `info` action and destination may you read [kctf-official-helper](../kctf-official-helper/SKILL.md) and query KernelCTF target, configuration, and public artifact information.

## Scope and Authorization

- First read repository `AGENTS.md` and follow its authorization, isolation, model assignment, and artifact rules.
- Perform **static analysis only**. Source inspection, read-only history research, static analyzers, and documentation may run on the host.
- Do not run PoCs, fuzzers, kernel-affecting workloads, create VMs, dynamically reproduce defects, experiment with exploitability, or develop exploits or patches. Even if requested, hand those stages off under their dedicated skills and explicit authorization.
- Access public source, patches, and rules read-only. Do not upload, submit, contact third parties, or disclose without separate instructions.
- Keep all research artifacts under `agent/<research-name>/`.

## Starting Conditions

The orchestrator establishes and records these in `agent/<research-name>/scope.md`:

- Target repository and exact revision (commit or equivalent identifier)
- Audit scope and explicit exclusions
- Threat model: attacker's starting privileges, trust boundary, expected impact
- Applicable build configuration, feature flags, deployment environment
- Time, token, and target-count limits and completion conditions

Conservatively infer unspecified values from the current repository and request, but explicitly label uncertainties that could change candidate verdicts as assumptions. Mark results provisional if the exact revision cannot be identified.

### Preliminary KernelCTF Eligibility Gate

For KernelCTF discovery, check the current [official rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md), active targets, LTS targets, and configurations through read-only access at the start, recording lookup times and URLs in `scope.md`. Track at least these independently:

- `Freshness`: Is it a zero-day with no mainline fix commit and no disclosure in a disallowed form?
- `Duplicate`: Are there existing submissions or public issues sharing the root cause or covered by the same fix?
- `Target-build`: Are the code and attack surface actually included in the active hardened target?
- `LTS-trigger`: Can the same root cause be triggered on the latest LTS target required by the rules?
- `Attacker`: Is it reachable under official starting UID/GID, capabilities, namespaces, and disabled-subsystem conditions?
- `Contract`: Is there a plausible route to meeting current runtime, stability, trigger-argument, and packaging requirements?

Leave duplicate/freshness questions that public information cannot resolve as `UNKNOWN`. Do not run remote evaluations or consume submission windows at this stage. Accessing official services through `kctf-official-helper` is a separate task requiring user authorization for action and destination; prefer public release information when available.

## Agent Assignment

For kernel research, assign exploration and analysis to the `kernel_astra` role using the actual model `gpt-6-astra`. Verify role and model in task creation results. If unavailable or rejected, do not substitute another model; preserve handoff materials and suspend only this stage.

The orchestrator directly manages both passes. Do not let exploration agents recursively create analysis agents. Add workers only when parallelism is useful, following these rules:

- Exploration workers own non-overlapping directories, subsystems, or interfaces.
- Analysis workers have exclusive ownership by audit target ID.
- Do not duplicate file or candidate assignments. Record needed independent rechecks as explicit `review` tasks.
- Workers write only their own files. Only the orchestrator updates shared indexes and `FINDINGS.md`.
- Where possible, use fresh analysis agents not anchored by exploration results. Pass structured audit-target records below rather than explorers' speculation.

## Stage 1: Exploration Agents

The goal is to identify portions of the code worth the cost of deep auditing, not declare vulnerabilities. Survey the assigned scope broadly and independently assess each surface along two dimensions.

### Reachability

- Is there a concrete entry point from low privileges or untrusted input?
- Which syscalls, file operations, ioctls, sockets, protocols, parsers, IPC, callbacks, or asynchronous work are involved?
- What privileges, namespaces, feature flags, devices, mounts, network state, or other prerequisites apply?

### Security Relevance

- Does it parse or copy input crossing a trust boundary?
- Does it manage object lifetimes, reference counts, shared state, permissions, credentials, memory sizes, or indices?
- Are there complex error recovery, asynchronous execution, lock transitions, type conversions, or variable-length data?
- Could a defect affect confidentiality, integrity, availability, or privilege boundaries?

Do not select code merely because a file is large or written in a memory-unsafe language such as C/C++. Conversely, include even small adapter functions if they pass attacker input across important lifetime or privilege boundaries.

### Exploration Artifacts

Write per-worker results to `agent/<research-name>/exploration/<worker-id>.md`. Each audit target has these fields:

```text
Target-ID: T-0001
Owner-scope: <exploration worker's assigned scope>
Code: <files, directories, key symbols>
Entry: <entry point originating with the attacker>
Reachability: high | medium | low | unknown
Security-relevance: high | medium | low
Boundary: <trust/privilege/lifetime boundary>
Attacker-control: <controllable values and constraints>
Preconditions: <privileges, configuration, state>
Dependencies: <callers, callees, and data structures to read together>
Why-audit: <concrete audit rationale>
Why-not: <reason for lower priority or exclusion>
```

Even when a specific bug hypothesis appears during exploration, retain only one or two sentences of observation. Do not begin deep analysis and blur scope ownership.

## Exploration → Analysis Handoff Gate

The orchestrator consolidates exploration results and exclusively writes `agent/<research-name>/targets.md`.

1. Merge surfaces involving the same entry point, object lifetime, or root cause.
2. Exclude or deprioritize surfaces unreachable under the current threat model.
3. Keep reachability and security relevance separate; do not combine them into an opaque single score.
4. Split oversized analysis units by call boundaries or object lifetimes; combine undersized units with neighboring code needed to understand invariants.
5. Record all inclusion/exclusion decisions with evidence so unaudited areas remain visible.

Generally prioritize targets high in `reachability × security relevance × attacker control`. Retain important boundaries with an `unknown` dimension if resolving it has reasonable cost.

## Stage 2: Analysis Agents

Read beyond assigned target files: follow handed-off `Dependencies` and actual call relationships to where invariants begin and end. Explain normal behavior before looking for defects.

1. Reconstruct concrete call and data flow from attacker input to sensitive operations.
2. Document invariants for ownership, reference counts, lengths, types, locks, state transitions, and permission checks.
3. Compare normal paths with error handling, cancellation, retries, release, asynchronous callbacks, and cross-thread paths.
4. Investigate lifetime errors, bounds/integer errors, races, uninitialized data, information disclosure, type confusion, missing permission checks, TOCTOU, and related possibilities according to code semantics. Do not use this list as a mere pattern-matching checklist.
5. Apply the falsification procedure below to every hypothesis, retaining only survivors as candidates.

Static analyzers, CodeQL, compiler diagnostics, `rg`, `git log`, and `git blame` provide leads. Do not promote them to candidates before directly verifying call paths and invariant violations in current source.

### Required Falsification

Answer at least these questions for each hypothesis:

- Is the entry point actually built and reachable in the current revision and configuration?
- Do earlier validation, length limits, permission checks, reference acquisition, locks, or serialization block the attack path?
- Do assumptions about error, release, and callback ordering hold across all relevant paths?
- Can the attacker actually control required values, timing, and object state?
- Do language, compiler, or runtime guarantees eliminate the suspected behavior?
- Is this already fixed, known, or a duplicate candidate with the same root cause?
- Does the outcome cross a security boundary, or is it an ordinary functional error or self-only failure?

Preserve falsified hypotheses with reasons and evidence locations. If missing code or configuration prevents judgment, use `NEEDS_CONTEXT` rather than filling gaps as facts.

### Candidate Records

Analysis workers record the following in `agent/<research-name>/analysis/<target-id>-<worker-id>.md`. Even without candidates, preserve investigated paths and important negative results.

```text
Candidate-ID: C-0001
Target-ID: T-0001
Status: HYPOTHESIS | SOURCE_CONFIRMED | REJECTED | NEEDS_CONTEXT
Revision/config: <exact target>
Class: <defect type>
Root cause: <one sentence>
Entry path: <symbol chain from attacker input to defect>
Attacker control: <values, objects, timing, and constraints>
Preconditions: <privileges, configuration, state>
Violated invariant: <expected invariant and actual violation>
Source evidence: <file:line, symbols, relevant branches>
Security consequence: <separate statically supported primitives from impact hypotheses>
Falsification: <defenses checked, falsification attempts, results>
Counterevidence/unknowns: <adverse evidence and unverified points>
Duplicate/fix check: <duplicate or fix status>
Next validation: <conditions for minimal dynamic validation; do not execute>
KernelCTF-eligibility: ELIGIBLE_CANDIDATE | INELIGIBLE | UNKNOWN | NOT_APPLICABLE
Eligibility evidence: <rules version, target/LTS inclusion, disclosure/patch/duplicate checks and unknowns>
```

`SOURCE_CONFIRMED` means call/data flow and invariant violation have been directly verified in current source under listed prerequisites. It does not mean runtime reproduction or exploitability is confirmed; this skill does not assign `DYNAMIC_CONFIRMED`. Separate observable primitives from higher-level security consequences needing further validation.

## Quality Gates and Prioritization

The orchestrator checks rather than simply merging candidates:

- Files, symbols, line numbers, configurations, and call paths match the current revision.
- No steps are missing between root cause and claimed primitive.
- Candidates with different entry points but the same invariant violation are grouped under one root cause.
- Reachability, static confidence, potential impact, and dynamic-validation cost are recorded separately.
- High-severity language does not exceed static evidence.

Assign independent static re-review to a fresh `kernel_astra` worker only for especially important candidates or conflicting analyst judgments. Do not impose a conclusion; provide original code, threat model, and candidate records to test whether the same causal relationship independently holds.

## Completion and Handoff

Finish static discovery when:

- All assigned scope is classified as audit targets, exclusions, or unreviewed areas.
- Every selected audit target has been analyzed or has a concrete stopping reason.
- Every candidate has a status, static evidence, falsification results, prerequisites, and next validation step.
- Candidates have been deduplicated and rechecked on the latest target revision.

Concisely collect only the following in `agent/<research-name>/FINDINGS.md`:

- Target revision, threat model, verified actual roles/models
- Exploration scope and coverage, excluded and unreviewed areas
- Prioritized `SOURCE_CONFIRMED` and `HYPOTHESIS` candidates
- Important `REJECTED` results and evidence preventing redundant exploration
- `NEEDS_CONTEXT` items and required inputs
- Evidence paths and file hashes for the next stage

If no candidates are found, do not generalize to “no vulnerabilities.” Report that no static candidates were confirmed within the audited scope, applied threat model, and remaining blind spots. When the budget ends, stop generating new hypotheses and preserve coverage and unfinished items.

## Design Rationale

This two-stage structure follows the approach in OpenAI's [A thousand fewer paths to root](https://openai.com/ko-KR/index/a-thousand-fewer-paths-to-root/): first narrow audit surfaces by reachability and security relevance, then have separate analysis agents understand behavior and the threat model before finding candidates. Operations remain deliberately simple, prioritizing fewer early false positives to reduce subsequent dynamic-validation costs and human review burden.

