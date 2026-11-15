---
name: vuln-discovery
description: Statically audit a kernel source tree for vulnerability candidates in kenv. A cost-efficient model selects code an unprivileged attacker can reach and maps each subsystem's key objects (where they are allocated, published, used, and freed). The strongest model then tracks object state across functions and files to find use-after-free caused by broken concurrency or lifetime management, and out-of-bounds access caused by unvalidated user values, and actively falsifies each hypothesis. Earlier agents' results in agent/ are re-verified, not trusted. Use for source audits, vulnerability discovery, static triage, and re-checking earlier audit verdicts; not for running PoCs, dynamic validation, or patching.
---

# Vulnerability Discovery

Narrow a large codebase in two passes that run on different model tiers.
Deliver a small set of candidates with verifiable static evidence, and keep
the negative results.

1. **Scout pass** (cost-efficient model): select code an unprivileged
   attacker can reach. Then map the main objects of each selected
   subsystem: where they are allocated, published, used, released, and
   freed.
2. **Analyst pass** (strongest model): starting from that map, work out how
   the attacker can drive each object's state. Look for objects freed while
   another path still uses them. Look for user-originated values used in
   index, size, or offset arithmetic without adequate validation. Track
   state across functions and files, and try to falsify every hypothesis.
3. **Re-verification** (strongest model): re-derive verdicts from earlier
   work in `agent/`, and the important verdicts of this run, instead of
   inheriting them.

The goal is fewer, better candidates, not a large count. Scanner warnings,
suspicious-looking code, model explanations, and earlier agents' verdicts
are leads, not findings.

## Scope

- Follow root `AGENTS.md` (isolation, VM naming, artifact locations).
- **Static only.** Source reading, `git log`/`git blame`, `rg`, compiler
  diagnostics, static analyzers, and public documentation may run on the host.
- Do not build-and-run PoCs, fuzz, boot VMs, or write patches in this stage.
  Those belong to `dynamic-validation` and `patch-generation`.
- Read public rules, source, and patches read-only. Do not contact third
  parties, upload, submit, or disclose.
- Write everything under `agent/<research-name>/`. You may read other
  research directories but never edit them.

## Execution model

The two passes need different strengths. Scouting and object mapping are
broad and search-heavy, and their output is `path:line` facts that can be
checked mechanically, so a cost-efficient model is enough. Analysis has to
keep many functions, files, locks, execution contexts, and object states in
view at once. Lifetime and synchronization bugs are where weaker models
miss, so analysis gets the strongest model and the highest effort. Spend the
budget there.

| Work | Who | Agent tool settings |
|---|---|---|
| Scope record, prior-work intake, gates, `targets.md`, `FINDINGS.md` | Orchestrator (session model) | — |
| Scout (§2a), object map (§2b) | One worker per scope or per target | `model: "sonnet"` |
| Analyst (§3), re-verifier (§1, §4) | One worker per target or per claim | `model: "fable"`, `effort: "max"` |

- This tiering is the user's standing instruction for this skill. Dispatch
  the workers without asking again. The user can override the models for a
  given request.
- If `fable` is unavailable or declines the task, use `opus` for analysts
  and re-verifiers, and record that you did.
- Do not use `haiku` for either pass. Anything the object map misses, the
  analyst never examines.
- Use `subagent_type: "general-purpose"`, because workers write their own
  file. Dispatch independent workers in one message, and wait for the whole
  pass before running its gate.
- Workers read their own instructions. Send them paths and IDs, not a
  paraphrase of the procedure:
  - scout and object map: `references/scout-object-map.md`
  - analyst and re-verifier: `references/analyst-lifetime-bounds.md`
- Give scouts non-overlapping directories, subsystems, or interfaces. Give
  each analyst exclusive ownership of specific Target-IDs.
- Hand analysts the target record and the verified object map. Do not hand
  them scout leads or earlier verdicts, so the analysis is not anchored on
  them.
- Workers write only their assigned file. Only the orchestrator writes
  `scope.md`, `targets.md`, and `FINDINGS.md`.
- Every record carries `Produced-by: <model, effort>`.
- If no subagent facility is available (another runtime, or dispatch is
  denied), run the passes yourself in order and record the model actually
  used. Label any analysis done below the analyst tier. Later runs treat
  that label as a re-verification trigger.

Dispatch prompts. Paths are absolute so that workers need no inherited
context:

```text
Scout (model "sonnet")
  Follow Part A of /workspace/.claude/skills/vuln-discovery/references/scout-object-map.md.
  Research dir: /workspace/agent/<research-name>/ (read scope.md first).
  Owner-scope: <directories / interfaces>. Write only exploration/<scope-id>.md.
  Return: Target-IDs written, excluded and unreviewed areas, leads.

Object map (model "sonnet")
  Follow Part B of the same file for <T-ID> as recorded in targets.md.
  Research dir: /workspace/agent/<research-name>/. Write only objects/<T-ID>.md.
  Return: objects mapped, rows per kind, unresolved items, leads.

Analyst (model "fable", effort "max")
  Follow /workspace/.claude/skills/vuln-discovery/references/analyst-lifetime-bounds.md for <T-ID>.
  Research dir: /workspace/agent/<research-name>/.
  Inputs: scope.md, the <T-ID> entry in targets.md, objects/<T-ID>.md.
  Write only analysis/<T-ID>.md.
  Return: Candidate-IDs with status and decisive question, inventory corrections, coverage gaps.

Re-verifier (model "fable", effort "max")
  Follow the same analyst file as a re-verifier.
  Research dir: /workspace/agent/<research-name>/.
  Claim under test: <the verdict, and for REJECTED the guard it relies on, in one or two sentences>.
  Inputs: scope.md, <target code and entry>, <object map if one exists>.
  Earlier record: <path>. Open it only after writing your own verdict.
  Write only reverify/<original-id>.md.
```

## 0. Scope record

Write `agent/<research-name>/scope.md` before auditing:

- Source tree path, which is the root that all `path:line` citations are
  relative to, and the exact revision (`git rev-parse HEAD`, or the release
  tag plus a local diff hash when it is not a git checkout)
- Exact config file and its SHA-256 (for example `configs/kernelctf.config`),
  and whether `KOBJ/.config` matches it after `olddefconfig`
- Audit scope and explicit exclusions
- Threat model: attacker start (UID/GID, capabilities, namespaces available),
  trust boundary, expected impact class, and the timing aids the attacker
  may use (for example whether userfaultfd or FUSE is available without
  privileges)
- Budget: time or target count, and the stopping condition
- Models used for each pass (see Execution model)
- `Prior work` table (§1)

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

## 1. Prior work in `agent/`

Earlier research in `agent/` was produced by other agents. It was often
done on a different revision, config, threat model, or model, and sometimes
with weaker reasoning than this skill requires. Treat its verdicts as
hypotheses. Its `REJECTED` results matter as much as its candidates: a
wrong rejection that is inherited unchecked hides a real bug from every
later run.

Before scouting, find earlier work on the same tree, subsystems, files, or
symbols. Run `rg -l` over `agent/` for paths and key symbols, then read each
hit's `FINDINGS.md`, `targets.md`, and records. Record each relevant item in
a `Prior work` table in `scope.md`:

| Item | Path @ SHA-256 | Its revision / config / threat model | Claimed verdict | Produced-by | Decision | Reason |
|---|---|---|---|---|---|---|

Decisions:

- `RE-VERIFY`: re-derive it as described below before it affects this run.
- `SPOT-CHECKED`: revision, config, and threat model match, hashes match,
  cited lines pass the citation check, and any rejection names a concrete
  guard. Use it to order work, and cite it as "inherited, spot-checked".
  Never promote it to `SOURCE_CONFIRMED` without re-deriving it.
- `LEAD-ONLY`: not checked. Use it as a pointer only. Any area it claims as
  audited counts as unreviewed in this run.
- `OUT-OF-SCOPE`: unrelated to this run.

The same rules apply to records written by earlier sessions of this
research.

### When to re-verify

Re-verify an item when any of these holds:

- The verdict decides something now: it would exclude a target, close a
  lead, or send a candidate to `dynamic-validation`.
- Its revision, config, or threat model differs from this run's, or is not
  recorded.
- Evidence is missing, a SHA-256 does not match, or a cited `path:line` does
  not match the pinned source (use the citation check in Gate B).
- The verdict rests on priors instead of mechanisms. Examples: "mature",
  "heavily reviewed", "byte-identical to <other tree>", "fuzzers would have
  found it", "unlikely", or "no concrete race found" without a free/use
  relation analysis.
- A lifetime or race verdict reasons one function at a time, with no
  release-side inventory or free/use relations. Likewise, a bounds verdict
  that lacks the value flow from source to sink.
- Program eligibility was folded into the technical verdict, for example
  `REJECTED` because the code is not in the LTS target. Split the two; the
  technical question is still open.
- A lifetime or concurrency verdict was produced below the analyst tier, or
  its producer is unknown.
- An earlier `NEEDS_CONTEXT` or "not fully falsified" item now has its
  missing input available.

Otherwise, mark the item `SPOT-CHECKED`, `LEAD-ONLY`, or `OUT-OF-SCOPE` and
record why. Re-verifying everything wastes the budget, and re-verifying
nothing inherits other agents' mistakes.

### How to re-verify

- Use a fresh re-verifier at the analyst tier. Give it the claim under test,
  the target, the threat model, and an object map if one exists. Do not give
  it the earlier reasoning. It derives its own verdict first, then reads the
  earlier record and explains every disagreement.
- For an inherited `REJECTED`, the re-verifier also tests the cited guard
  directly. Is the guard present at that location in this revision, and
  does it cover every path, including error paths, async paths, and
  alternate entries?
- The re-verifier writes `reverify/<original-id>.md` as a candidate record
  with `Provenance: inherited <path>@<sha256>` and
  `Reverification: SAME | CHANGED <old> → <new>`. Do not edit the other
  research directory.
- If you decide not to re-verify an item that matters, record
  `Reverification: NOT_DONE <reason>` and keep its area out of this run's
  audited coverage.

## 2. Scout pass (cost-efficient tier)

### 2a. Reachable surfaces

Scouts follow Part A of `references/scout-object-map.md`. They enumerate the
entry points in their scope, decide privilege and config gates from code,
rate **reachability** and **security relevance** separately, and write
target records to `exploration/<scope-id>.md`.

### Gate A: targets

Consolidate into `agent/<research-name>/targets.md`:

1. Merge surfaces that share an entry point, object lifetime, or root cause.
2. Drop or deprioritize surfaces unreachable under the threat model or config.
3. Split oversized units at call or lifetime boundaries; merge undersized
   units with the code needed to understand their invariants.
4. Record every include/exclude decision with evidence, so unaudited areas
   stay visible as coverage gaps.
5. Set the number of analyst targets from the budget. Analyst runs are the
   main cost.

Prioritize by reachability × security relevance × attacker control. Keep
`unknown` reachability targets when resolving the unknown is cheap. Use
scout leads only to order the work, and do not copy them into `targets.md`.

### 2b. Object maps

For each selected target, an object-map worker follows Part B of the same
file and writes `objects/<target-id>.md`. The map contains:

- the main objects, their lifetime rules, and their containers
- every alloc, publish, get, put, unpublish, free, async, and error-unwind
  site, plus the use sites that matter for lifetime (Part B says which),
  each with `path:line`, execution context, and locks held
- user-controlled fields and their checks
- the concurrency surface and the attacker's operations on each object

### Gate B: verify each map

The analyst starts from the map's release side, so check the map before
handing it over:

1. Run the citation check. Every cited line must exist and show the cited
   symbol. Check all release-side rows, and at least five use rows from
   different entry points:

   ```bash
   KSRC=<source root from scope.md>; F=agent/<research-name>/objects/<T-ID>.md
   grep -oE '[A-Za-z0-9_./+-]+\.(c|h|S|rs):[0-9]+' "$F" | sort -u |
   while IFS=: read -r f l; do
     if [ -f "$KSRC/$f" ]; then printf '%s:%s: %s\n' "$f" "$l" "$(sed -n "${l}p" "$KSRC/$f")"
     else printf '%s:%s: MISSING (path must be relative to the source root)\n' "$f" "$l"; fi
   done
   ```

2. Re-run the map's recorded release-side searches. A hit that is neither
   in the tables nor explained means the map is incomplete.
3. Confirm that each object has every row kind filled, or explicitly marked
   `none found` or `unresolved`. Confirm that the tables contain facts, not
   verdicts.

Record `Map-status: VERIFIED` or `Map-status: INCOMPLETE <gaps>` for the
target in `targets.md`. Send an incomplete map back once with the specific
gaps, either to the same worker with SendMessage or to a new one. If it is
still incomplete, hand it to the analyst marked `INCOMPLETE` so the analyst
rebuilds those parts. Never pass on a map you have not checked.

## 3. Analyst pass (strongest tier)

One analyst per target follows `references/analyst-lifetime-bounds.md`, with
the target record and the verified object map as inputs. In short:

1. Rebuild the release side from source, and report `Inventory corrections`.
2. Model what the attacker can do to each object. Write its state machine,
   and mark which transitions the attacker can trigger repeatedly, out of
   order, concurrently, or against an async context.
3. Lifetime and concurrency:
   - Justify every reachable use: reference, lock, RCU, owner pin, or
     teardown ordering.
   - Relate every free-side site to every use in a table.
   - Balance references across functions.
   - Write a concrete interleaving for each surviving candidate.
4. Untrusted values: follow each user-originated value to index, size, and
   offset sinks. Trace it across functions, files, and time, including
   stored fields that later entries read. Test every check against the real
   bound, and give a concrete passing value for each surviving candidate.
5. Verify API contracts in the pinned tree, falsify, and answer each
   hypothesis's decisive question before closing it.

Explain the normal behavior first. Most real kernel bugs live in teardown,
error, and concurrent paths. Use-after-free and out-of-bounds access are
the primary questions. Record other defect classes found along the way,
held to the same evidence bar.

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
- Does the argument rely on an API contract (wait semantics, reference
  semantics, RCU rules)? Cite the definition in the pinned tree, not memory.
- Is it already fixed upstream or in a stable branch? Check `git log -S`/`-G`
  on the symbols, and mainline/stable history newer than the target.
- Does the outcome cross a security boundary, or is it a functional bug or a
  self-only failure?

Keep falsified hypotheses with the reason and the evidence location. If
missing code or config prevents a decision, use `NEEDS_CONTEXT`. Do not fill
the gap with guesses. "Mature code", "identical to another tree", and
"unlikely" are priors. They can order the work, but they cannot decide a
verdict.

### Candidate record

Write `agent/<research-name>/analysis/<target-id>.md`. Keep investigated
paths and negative results even when nothing survives.

```text
Candidate-ID: C-0001
Target-ID: T-0001
Status: HYPOTHESIS | SOURCE_CONFIRMED | REJECTED | NEEDS_CONTEXT
Revision/config: <exact tree, commit, config hash>
Produced-by: <model, effort>
Provenance: new | inherited <path>@<sha256>
Reverification: SAME | CHANGED <old> → <new> | NOT_DONE <reason> | n/a
Class: <manifestation via mechanism, e.g. UAF via close/ioctl race; OOB write via off-by-one index check>
Root cause: <one sentence>
Fix locus: <where a correct fix would go; used for dedup>
Entry path: <symbol chain from attacker input to defect>
Attacker control: <values, objects, timing, constraints>
Preconditions: <privileges, namespaces, config, state>
Violated invariant: <expected invariant and how it breaks>
Mechanism: <lifetime/race: the interleaving; bounds/integer: the value flow and a concrete passing value>
First invalid operation: <function, path:line, read/write, object and field>
Source evidence: <path:line, symbols, branches>
Decisive question: <the fact that settles the verdict; answer; evidence>
Effect: <what the defect statically causes, e.g. UAF write of N bytes in kmalloc-192>
Impact hypothesis: <consequence needing runtime or human confirmation>
Falsification: <defenses checked, attempts, results>
Counterevidence/unknowns: <adverse evidence, unverified points>
Duplicate/fix check: <commands run, commits found>
Next validation: <minimal trigger idea, diagnostics needed (KASAN/KCSAN/...); do not execute>
KernelCTF-eligibility: ELIGIBLE_CANDIDATE | INELIGIBLE | UNKNOWN | NOT_APPLICABLE
Eligibility evidence: <rules URL/time, target and LTS inclusion, unknowns>
```

`SOURCE_CONFIRMED` means the call/data flow and the invariant violation were
read directly in current source under the listed preconditions. For a
lifetime or race defect, that includes the free/use relation and a
permitted interleaving. For a bounds or integer defect, it includes the
full value flow and a concrete passing value. It does not mean the bug
reproduces or that impact is confirmed. This skill never assigns
`DYNAMIC_CONFIRMED`.

Keep the technical status separate from program eligibility. A valid defect
outside a program's scope stays `SOURCE_CONFIRMED` or `HYPOTHESIS` with
`KernelCTF-eligibility: INELIGIBLE`. It is never `REJECTED` for that reason.

## 4. Quality gate and dedup

Before handing off, check that:

- Files, symbols, line numbers, config options, and call paths match the
  pinned revision. Run the Gate B citation check on every analysis and
  re-verification file.
- No step is missing between the root cause and the claimed effect. A
  lifetime candidate needs its relation row and a permitted interleaving,
  and a bounds candidate needs a value flow and a concrete passing value.
  Without them, the candidate stays `HYPOTHESIS`.
- Analysts' `Inventory corrections` are merged into the object maps. If the
  corrections show that a scout systematically missed something, such as a
  kind of release path or an ops table, re-check that scout's other maps
  for the same miss.
- **Candidates are deduplicated by fix, not by symptom.** Two entry points
  that a single patch would close are one root cause. One entry point that
  needs two independent patches is two candidates.
- Reachability, static confidence, potential impact, and validation cost are
  recorded separately.
- Severity wording does not go beyond the static evidence.

Every `SOURCE_CONFIRMED` candidate, and any candidate that the analyst or
the orchestrator marks as disputed, gets an independent re-verification (see
"How to re-verify" in §1) before it leaves this stage. To the next stage, a
single analyst's conclusion is one more earlier agent's output.

Consolidate without rewriting. `FINDINGS.md` links each candidate record and
keeps its class, location, mechanism, and first invalid operation as the
record states them. Paraphrasing during consolidation is how findings get
lost or quietly changed.

## 5. Completion

Static discovery is complete when:

- All assigned scope is classified as audited, excluded, or unreviewed.
- Every selected target is analyzed or has a concrete stopping reason.
- Every candidate has a status, evidence, falsification results,
  preconditions, and a next validation step.
- Every prior-work item that affected this run has a recorded decision.

Update `agent/<research-name>/FINDINGS.md` with:

- Revision, config hash, threat model
- Models and efforts used for each pass
- Coverage: audited, excluded, and unreviewed areas, with the map status of
  each target
- Prioritized `SOURCE_CONFIRMED` and `HYPOTHESIS` candidates
- Important `REJECTED` results with the guard that rejects each, to prevent
  redundant re-exploration
- `NEEDS_CONTEXT` items and the inputs they need
- Prior-work decisions and re-verification outcomes
- Evidence paths and SHA-256 for the next stage

If nothing survives, do not write "no vulnerabilities." Write that no
candidate was confirmed within the audited scope, the threat model, and the
listed blind spots.

## Background

The Scout → Analyst structure follows OpenAI's
[A thousand fewer paths to root](https://openai.com/index/a-thousand-fewer-paths-to-root/):
pick low-privilege-reachable targets first, audit each one deeply, and
count distinct bugs by the separate patch each needs.

The object map, the model tiers, and the relation and value-flow
requirements respond to failure modes measured in "How Effectively Do
Security Skills Guide Coding Agents in Vulnerability Detection in Linux
Kernel?" ([arXiv:2610.25705](https://arxiv.org/html/2610.25705v1)), a study of
security skills run against 100 Linux kernel CVEs:

- Agents found local bounds bugs (one index, length, or offset) several
  times more often than lifetime and synchronization bugs, which need
  relations across functions.
- The most frequent agent failure was relevant evidence that was never
  analyzed. Another common failure was a required state relation that was
  never built: a free and a timeout path were both found but never linked
  into a use-after-free.
- Results depended on the executing model. The lightweight model scored
  lowest and gained least from better procedures.
- The more effective skills kept a hypothesis open until a decisive check
  resolved it, verified relations against source, and kept the mechanism,
  class, and location in the final output.

The record formats, tiers, and gates are this repository's own choices.
