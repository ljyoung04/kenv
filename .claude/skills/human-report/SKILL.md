---
name: human-report
description: Cross-check a kernel vulnerability's root cause, minimal reproducer, patch, and limits against original evidence, and assemble a bundle a human can independently verify. Use for final technical review and kernelCTF requirement review; does not submit, disclose, or contact anyone.
---

# Human Review Bundle

Assemble the pipeline output so that a human can rebuild and judge it from
the original evidence. This is the last quality gate: it checks the evidence
behind every claim and exposes gaps. It is not a polishing pass.

## Scope

- Read root `AGENTS.md`, `scope.md`, `FINDINGS.md`, and every discovery,
  validation, and patch artifact for the candidate. Mark stages that were
  not run or not authorized as `not performed`.
- Do the review yourself, from the originals rather than from earlier
  summaries. If the user asks for subagents, use a reviewer that did not
  produce the key results.
- Subagents, when used: in kernelCTF research `model: "opus"` (Opus 5.5),
  `effort: "max"`; otherwise `model: "opus"` with no effort set. A model or
  effort the user names for the request wins. Record the model ID and effort
  used; on a model error retry once with the same settings, then do the work
  yourself rather than switching models.
- Write to `agent/<research-name>/human-report/<vuln-name>/`. Do not edit
  originals or other tasks' reports. Link large originals by relative path
  and hash instead of copying them.
- Preparing a report does not authorize sending it anywhere.

## Evidence chain

Check that IDs are consistent across stages, then check each link:

```text
attacker entry point
  -> violated invariant and first invalid operation
  -> reproducer's runtime observation (matches the candidate, not another bug)
  -> invariant restored by the patch
  -> reproducer and functional regression results
```

Every arrow needs source locations, config, original logs, and controls.
Do not hide a missing link. Verify independently that:

- Paths, symbols, line numbers, commits, configs, and hashes match the
  actual files. Re-hash them.
- The reproduction exercises the designated root cause, not a different
  bug or an infrastructure fault. Compare the sanitizer report's site and
  object with the predicted first invalid operation.
- Claims of unprivileged execution, instrumentation, and target match
  reflect the recorded environment.
- Success denominators, time limits, failure types, and fresh-VM conditions
  are preserved.
- The patch fixes the root cause and its variants without regressions, and
  does not merely block the reproducer.
- Severity statements stay within the demonstrated effect and
  reachability.

Do not change originals to resolve a discrepancy. Record its impact and the
stage that must redo the work in `review-findings.md`. Do not assign
`READY_FOR_HUMAN_REVIEW` while an essential link is broken.

## Bundle layout

```text
review-findings.md
MANIFEST.sha256
docs/
  vulnerability.md
  reproduction.md
  patch.md
  limitations.md
evidence/
  index.md
repro/
patch/
  fix.patch
  commit-message.txt
```

- `vulnerability.md`: summary, affected revisions and configs, threat model,
  entry path, root cause, invariant, first invalid operation, runtime
  evidence, demonstrated effect. Use the writing style of
  `references/example1.md` and `references/example2.md`: a precise
  interleaving or call chain, the exact object and offset, and why
  sanitizers do or do not catch it. The disclosure timeline in
  `example1.md` is outside this workflow; do not copy that part of its
  structure.
- `reproduction.md`: setup commands kept separate from attacker actions,
  expected output, failure diagnosis, successes out of total.
- `patch.md`: design, base revision, apply/build/regression/variant results,
  remaining risks, suggested recipients from `get_maintainer.pl`.
- `limitations.md`: every unverified impact claim and anything this
  workflow does not cover.

Every important claim must trace through `evidence/index.md` to an original
file, hash, and location. Do not copy kernel images, `vmlinux`,
certificates, tokens, other secrets, or personal data into the bundle.

## KernelCTF review mode

When asked, re-check the current
[rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md),
active targets, LTS trigger requirement, disclosure and patch timing,
duplicate rules, and required submission material. Saved target names and
old schemas are not authoritative.

```text
kernelctf/
  eligibility-review.md
  requirements.md
  evidence-index.md
```

Mark freshness, duplicate status, target inclusion, unprivileged
reachability, LTS reproduction, stability, disclosure and patch timing, and
evidence availability as `PASS`, `FAIL`, `UNKNOWN`, or `OUT_OF_SCOPE`, with
lookup time and URLs. Requirements beyond discovery, minimal reproduction,
patching, and review are `OUT_OF_SCOPE`; the user handles them. Do not
create placeholder artifacts for them or claim submission readiness.

## Final verdict

| Status | Criteria |
|---|---|
| `READY_FOR_HUMAN_REVIEW` | Evidence chain and required docs are complete; a human can re-run the documented commands |
| `KERNELCTF_REQUIREMENTS_REVIEWED` | Current program requirements and coverage gaps are recorded; this is not a readiness verdict |
| `NEEDS_REWORK` | An essential discrepancy exists in causality, reproduction, patch, or docs |
| `NEEDS_USER_DATA` | A required value the agent cannot invent is missing |
| `INCOMPLETE_EVIDENCE` | Missing originals or hashes prevent independent verification |

Start `review-findings.md` with the verdict, the reviewed revisions and
targets, key confirmed facts, blocking issues, and exact next actions.
Finally, run `sha256sum -c MANIFEST.sha256` and follow the documented links
and commands read-only from a clean directory, to catch hidden state.

## Background

Keeps the human-review bundle from OpenAI's
[A thousand fewer paths to root](https://openai.com/index/a-thousand-fewer-paths-to-root/):
root-cause analysis, minimal crashing PoC, and candidate patch, all reviewed
by humans before reporting.
A verdict here does not replace human judgment or a program's eligibility
decision.
