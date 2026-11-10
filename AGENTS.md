# AGENTS.md — kenv Working Rules

These rules apply throughout this repository. Apply only relevant rules to ordinary code and documentation work; for kernel research, read the stage-specific skills below. This file defines authorization, isolation, and model assignments; skills define procedures and artifact requirements. User instructions and higher-priority system instructions take precedence.

Organize all artifacts generated during work under `agent/`, except kernel images and sources, which belong under `kernels/`.

## Repository and Execution

- `tools/vm.sh`, `tools/kernel.sh`, and `tools/fs.sh` initialize their own paths. Do not source `env.sh` on every Bash invocation. Shell shortcuts such as `envlx`, `vm`, `kernel`, and `connect` are user conveniences; agents use explicit CLI commands.
- For profile operations, pass `-p <profile>` before the subcommand; for VM operations, pass `-p <profile> -v <vm>`. Place `--` before SSH remote commands. Do not infer targets from previous commands, aliases, or inherited environments.
- Key locations: `kernels/` for kernel sources and build outputs, `configs/` for configuration fragments, `images/` for guest filesystem images, `profiles/<p>/profile.sh` for configuration, and `profiles/<p>/vms/<v>/` for VM state. Configuration files are sourced as executable code; verify their provenance and contents.
- Keep research code, PoCs, exploits, logs, patches, notes, and final review materials under `agent/<research-name>/`; create it if needed. `agent/` and the skill installation directory `.agents/` are different directories. Preserve originals in `user/`, `save/`, other tasks' artifacts, and reference PoCs. As under the existing rules, do not read or use `reports/` as evidence.
- `tmp/AGENTS.md` and translations are reference copies of earlier rules. Current procedures are defined by this root file and `.agents/skills/`. Do not search for nonexistent `agents/*.md` files.

## Models and Task Assignment

| Task | Model ID |
|---|---|
| 1. Audit target selection, vulnerability discovery, static analysis, candidate falsification | `gpt-6-astra` |
| 2. Minimal reproducers, KASAN/KCSAN dynamic validation | `gpt-6-astra` |
| 3. Static exploitability triage, independent causality review | `gpt-daybreak-blue-latest` |
| 3. Exploit strategy, implementation, debugging, reliability measurement | `gpt-daybreak-blue-latest` |
| 4. Minimal patch generation, regression and variant validation | `gpt-6-astra` |
| 5. Review material preparation, technical cross-review | `gpt-daybreak-blue-latest` |

Role definitions are in `.codex/agents/`. Reading a skill does not change the model. At the start of a research stage, the orchestrator assigns work to the corresponding role or exact model ID. If already running as the assigned model, proceed without unnecessary delegation. This model-specific research delegation is permitted. Research agents are not mandatory for ordinary repository maintenance.

Check the execution tool's supported models and actual creation result. If the specified model is unavailable or selection is rejected, do not silently substitute another model. Preserve handoff materials, suspend only that stage, and request model activation or explicit instructions for a replacement. Record the requested model separately from the verified actual model; do not claim use of an unverified model. When a new model is needed, create a new worker instead of merely relabeling an existing one.

Do not create duplicate workers with overlapping stages, targets, and decision criteria. For parallel workers, assign distinct ownership of candidates, files, and VMs; never modify the same VM or build output directory concurrently. Follow the skills below for detailed stage procedures and handoff criteria.

## Boundaries That Always Apply

1. Source inspection, builds, static analysis, documentation, and reviewed control scripts may run on the host. Run PoCs, exploits, binaries of unknown provenance, and reproduction workloads that load or alter the kernel only in task-owned local VMs or separately authorized official services. Development containers share the host kernel and do not count as guest isolation.
2. Do not modify the host kernel, modules, sysctl settings, firewall, mounts, block devices, or services; reboot, shut down, or exhaust host resources. Use `tracer.sh` only in guests. Research agents must not run `fs.sh create` or `create-image.sh` on the host because they perform mounts. Use prepared images; report when an image needs to be prepared.
3. Name VMs `<task>_<unix-timestamp>`, where `<task>` matches `[a-z0-9][a-z0-9-]*` and the timestamp is decimal Unix time in seconds. Check for collisions, including stopped VM directories, before creation; use a later timestamp if a collision occurs. `a`, `vm`, `vm1`, `test`, and `debug` are reserved for the user.
4. Record each created VM's profile, name, path, creation time, and owning task. Do not infer ownership from its name alone. Do not stop, delete, or reset another task's or user's VM without explicit delegation.
5. Transfer research files only with `tools/vm.sh ... scp`, marking guest paths with `vm:`. Do not substitute host sharing through `--shared`, 9p, virtiofs, `vmhttp`, or similar mechanisms.
6. Before running commands, patches, or tests, verify the exact target, arguments, side effects, and isolation. Record suspected test infrastructure or QEMU issues separately from kernel vulnerabilities; do not expand research into attacks on the host or isolation boundary.
7. Outputs from models, scanners, and previous agents are hypotheses until verified. Check paths, symbols, line numbers, configurations, diagnostics, and results against current source and evidence. Do not fabricate unsupported results.
8. Read-only access to public rules, patches, and sources is allowed. Consuming official attempts, uploading, submitting flags or forms, contacting third parties, and external reporting or disclosure require user instructions specifying the action and destination. Do not request authorization already granted. The presence of `connect.sh` or certificates does not authorize service use. Internal reports and `FINDINGS.md` require no separate authorization.

## Research Stages and Skills

At the start of research, identify which of the five stages the request covers. If multiple stages are authorized, proceed in order; do not interpret a discovery request as authorization for exploit development or external submission.

1. Vulnerability discovery: select audit targets, find static candidates, and attempt to falsify them.
2. Dynamic validation: produce minimal reproducers and KASAN/KCSAN evidence in isolated VMs.
3. Exploitability assessment: evaluate target impacts such as information disclosure, flag reads, and privilege escalation under the actual target's mitigations and privilege conditions.
4. Patch generation: create minimal root-cause fixes and validate regressions and variants.
5. Human review: have humans review the root cause, reproducer, exploit, patch, severity, and limitations.

| When applicable | Skill to read |
|---|---|
| Discovery, source audits, static triage, falsification, preliminary KernelCTF eligibility checks | [vuln-discovery](.agents/skills/vuln-discovery/SKILL.md) |
| Reproducers, KASAN/KCSAN, dynamic confirmation, crash causality validation | [dynamic-validation](.agents/skills/dynamic-validation/SKILL.md) |
| Exploitability triage, exploit development, target impact, success-rate measurement | [exploitdev](.agents/skills/exploitdev/SKILL.md) |
| Minimal patches, builds, regression, variant, and bypass validation | [patch-generation](.agents/skills/patch-generation/SKILL.md) |
| Human review evidence bundles, technical cross-review, final handoff | [human-report](.agents/skills/human-report/SKILL.md) |
| Authorized KernelCTF information queries and remote tests | [kctf-official-helper](.agents/skills/kctf-official-helper/SKILL.md) |

Read only applicable skills. Candidates pass through record completeness → static falsification/reproduction preparation → dynamic validation. Distinguish `SOURCE_CONFIRMED` from `DYNAMIC_CONFIRMED`; record reachability and exploitability as separate dimensions. Do not claim target impact from a crash or KASAN output alone. KernelCTF success need not require a root shell or conventional LPE: satisfying the current service's flag acquisition and success contract on the official target with the prescribed starting privileges can meet the goal. Verify exact flag paths, formats, and success criteria against official rules and the evaluation system at the time of work; do not infer them from past targets.

Before handoff or completion, record confirmed facts, useful primitives, important negative results, unresolved issues, and evidence paths and hashes in `agent/<research-name>/FINDINGS.md`. Do not overwrite other tasks' records. Verify the connection between root cause and outcome; do not count success from another vulnerability or relaxed experimental settings as success against the designated target.

## Orchestration and Stage Handoffs

Within the authorized scope, the orchestrator follows this order:

```text
vuln-discovery
  -> dynamic-validation
  -> exploitdev
  -> patch-generation
  -> human-report
```

At the end of each stage, the assigned worker records its verdict and original evidence paths and stops. The orchestrator directly checks the handoff files, then passes `research-name`, Candidate-ID, Target-ID, exact revision and configuration, the previous verdict, evidence paths and hashes, unverified assumptions, and stopping conditions to the next stage. Do not pass only a conversation summary or leave the next worker to guess the previous worker's directory.

Do not automatically advance candidates that fail the following gates.

| Handoff | Minimum gate |
|---|---|
| Discovery → validation | Entry path, violated invariant, and attacker control are documented in current source, and static falsification has been performed. |
| Validation → exploitability | `DYNAMIC_CONFIRMED`, with reproduction evidence linking the observed defect to the designated root cause. |
| Exploitability → patch | A verdict on the primitive or target impact exists; successful results have an independent causality review confirming use of the designated vulnerability. Dynamically confirmed vulnerabilities may be patched even when exploitation fails. |
| Patch → human review | The patch builds, and reproducer regression, functional regression, variant review, and remaining risks are documented. |

Failure of one candidate does not block others. Preserve terminal states such as `REJECTED`, `NOT_REPRODUCED`, `INFRA_BLOCKED`, and `NEEDS_CONTEXT` with evidence. If the next stage is outside user authorization, prepare the handoff only; do not execute it. Remote evaluation, flag submission, external reporting, and disclosure are not automatic pipeline stages.

For KernelCTF, recheck the [official rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md) at the start of work and final handoff. Do not assume fixed historical targets, LTS versions, or submission windows. Separately record 0-day/disclosure/patch status, duplicates, actual active targets and configurations, unprivileged reachability, LTS triggers, runtime and stability, and packaging requirements. Read `kctf-official-helper` additionally only when needed for these checks or authorized testing.
