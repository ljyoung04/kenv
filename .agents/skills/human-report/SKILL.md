---
name: human-report
description: Check kernel vulnerability research root causes, reproducers, exploit impact, patches, severity, and limitations against original evidence, and create reports and bundles for independent human review. Use for final technical review and KernelCTF package preparation; do not perform remote submission or external disclosure.
---

# Human Review Bundle

Organize pipeline results so humans can independently reconstruct and assess them from original evidence. This is a final quality gate that checks evidence for every claim and exposes inconsistencies, omissions, and unverified points, rather than merely turning earlier conclusions into a polished report.

## Scope and Roles

- Read root `AGENTS.md`, `scope.md`, `FINDINGS.md`, and all discovery, validation, exploitation, and patch artifacts for the candidate. Mark inapplicable or unauthorized stages as `not performed` rather than assuming they do not exist.
- Assign preparation and technical cross-review to `kernel_astra`/`gpt-6-astra` and record the actual role/model. Where possible, use a reviewer other than the worker who produced the key results.
- Create artifacts in `agent/<research-name>/human-report/<vuln-name>/`. Do not modify other tasks' reports or original logs. Large originals may be linked through stable relative paths and hashes instead of copied.
- Report preparation does not authorize external reporting, PRs, uploads, flag submissions, or disclosure. Perform those separately only when the user specifies the destination and instructs the action.

## Input Completeness

Verify consistent Candidate-ID and Target-ID across all stages and review these connections:

```text
Attacker entry point
  -> Violated invariant and first invalid operation
  -> Minimal reproducer's runtime observation
  -> Confirmed primitive
  -> Target impact and exact vulnerability used
  -> Invariant restored by the patch and regression results
```

Do not hide gaps where an arrow lacks source locations, configuration, original logs, or control experiments. Independently check in particular:

- Do files, symbols, line numbers, commits, configurations, and binary hashes match actual files?
- Do reproduction and exploit success use the same root cause, rather than another zero-day or infrastructure defect?
- Do claims of unprivileged execution, enabled mitigations, and target matching reflect the actual environment?
- Are success-rate denominators, time limits, failure types, and clean-VM conditions preserved?
- Does the patch address the root cause and variants without new regressions, rather than merely blocking the reproducer?
- Does severity stay within the demonstrated impact and reachability conditions?

Do not alter originals to reconcile discrepancies. Record their impact and required rework stage in `review-findings.md`. Do not assign `READY` when essential causal links fail.

## Report Structure

Use this default structure, but follow official naming requirements when the target program differs.

```
review-findings.md
MANIFEST.sha256
docs/
  vulnerability.md
  reproduction.md
  exploit.md
  patch.md
  limitations.md
evidence/
  index.md
  <required originals or relative-path list>
repro/
  <minimal reproducer and build/run files>
exploit/
  <exact-target>/
    exploit.c
    exploit
    Makefile
patch/
  fix.patch
  commit-message.txt
```

In `vulnerability.md`, include the summary, exact affected revisions/configurations, threat model, entry path, root cause, violated invariant, first invalid operation, runtime evidence, and impact verdict. In `reproduction.md`, separate preparation commands from attacker actions and include expected output, failure diagnosis, and successes/total attempts. In `exploit.md`, include goals, primitive chain, target mitigations, success evidence, reliability, and independent causal review; explicitly state if not performed. In `patch.md`, document fix design, base revision, application/build/regression/variant results, and remaining risks.

Every important claim must be traceable through `evidence/index.md` to original files, hashes, and relevant locations. Do not copy kernel images, vmlinux, certificates, tokens, flags, personal information, or secrets unnecessary for reproduction into the bundle.

## KernelCTF Package Mode

When KernelCTF review is requested, recheck the current [official rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md), submission structure, and [metadata schema](https://google.github.io/security-research/kernelctf/metadata.schema.v3.json) during final preparation. Do not treat saved target names or old schemas as authoritative current rules. Add the following inside the general bundle when consistent with current requirements:

```text
kernelctf/
  docs/
    vulnerability.md
    exploit.md
  exploit/
    <exact-target>/
      exploit
      exploit.c
      Makefile
  metadata.json
  original.tar.gz
  package-review.md
```

For `original.tar.gz`, preserve the original and its hash only when the exact archive used for official evaluation already exists. Do not call a newly packaged file the original submission. Verify that the prebuilt `exploit` matches its source and follows the current contract's arguments and limits without external dependencies.

Use the schema and [local example](references/example.json) only as structural references for `metadata.json`; do not copy example IDs, CVEs, commits, or versions. Do not invent values such as `submission_ids`, CVE, patch commit, or official stability that require user input or a publicly finalized state. If the current schema disallows empty values, do not pass validation with false values. Leave empty values in `metadata.draft.json` and list `NEEDS_USER_DATA` and required fields in `package-review.md`. Validate only a fully populated `metadata.json` against the current schema before marking it ready for submission.

Separately record official requirements for 0-day/disclosure/patch timing, duplicates, active targets and LTS triggers, stability/runtime, and submission deadlines as `PASS`, `FAIL`, or `UNKNOWN`, with lookup times and evidence URLs. Official-service execution and form/PR submission are not included in package preparation.

## Final Verdict

| Status | Criteria |
|---|---|
| `READY_FOR_HUMAN_REVIEW` | Evidence links and required documents are complete; a human can independently review using the documented commands. |
| `READY_FOR_AUTHORIZED_SUBMISSION` | In addition to human-review readiness, current program format, eligibility, and metadata are verified. Submission itself is not performed. |
| `NEEDS_REWORK` | Essential discrepancies exist in causality, reproduction, impact, patching, or documentation. |
| `NEEDS_USER_DATA` | Required values the agent cannot invent, such as submission IDs or CVEs, are missing. |
| `INCOMPLETE_EVIDENCE` | Missing originals or hashes prevent independent verification. |

Begin `review-findings.md` with the verdict, reviewed revisions/targets, verified roles/models, key confirmed facts, blocking issues, and exact next actions. Finally verify `MANIFEST.sha256` and follow links and commands read-only from a clean working directory to check for missing implicit state.

## Design Rationale

Reflects the final human review of root cause, minimal PoC, patch, complete exploit, and proposed severity, and the need for independent validation of successful paths, in OpenAI's [A thousand fewer paths to root](https://openai.com/ko-KR/index/a-thousand-fewer-paths-to-root/). Readiness verdicts from this skill do not replace final human judgment or an external program's eligibility decision.
