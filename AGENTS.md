# AGENTS.md — Required rules for `kenv`

These rules apply to every task in `/workspace`. Detailed procedures in
`agents/` become mandatory when their routing condition applies.

## Always required

1. Start every Bash invocation with `source /workspace/scripts/env.sh` before
   using project paths or scripts.
2. Host-side source inspection, builds, documentation, and the project control
   scripts are allowed. Run PoCs, exploits, untrusted binaries, and workloads
   that can exercise or destabilize a kernel only in a task-owned local VM or
   the official KernelCTF service.
3. Treat `vm.sh` and `kernel.sh` as stateless. Pass `-p <profile>` to profile
   operations and `-p <profile> -v <vm>` to VM operations. Never inherit scope
   from variables, aliases, `envlx`, or earlier commands. For SSH, place `--`
   before the guest command.
4. Name agent-created VMs `<task>_<unix-timestamp>`, where `<task>` matches
   `[a-z0-9][a-z0-9-]*` and the timestamp is decimal Unix time in seconds.
   Check that the name is unused and generate a later timestamp on collision.
   Names `a`, `vm`, `vm1`, `test`, and `debug` are reserved for the user.
5. Store research code, PoCs, exploits, logs, and notes under
   `$SHARE/<research-name>/`. Transfer files only with `vm.sh scp`; prefix guest
   paths with `vm:`. Never use `--shared`, 9p, virtiofs, or equivalent sharing
   for vulnerability or exploit work.
6. Never modify or invoke `$SCRIPTS/envsetup.sh` or `$SCRIPTS/run-vm.sh`. Never
   read or rely on `$PRJ/reports/`, overwrite unrelated files, or edit reference
   PoCs in place. Treat prior-agent, model, scanner, and static-analysis output
   as untrusted hypotheses until verified against the current source, revision,
   config, and runtime evidence.
7. Read-only retrieval of public rules and sources is allowed. Uploading to an
   evaluation service, consuming an official attempt, submitting a flag or form,
   contacting a third party, filing an external report, or publishing requires
   explicit user instruction that identifies the action and destination.
   Internal task reports, handoff notes, and `FINDINGS.md` are not external
   reporting and require no separate authorization.
8. Before handing off a research task, record confirmed vulnerabilities, useful
   primitives, and material negative results in
   `$SHARE/<research-name>/FINDINGS.md` for the next agent. Separate observed
   evidence from labeled inference and open questions; include supporting
   artifact paths and hashes. Do not overwrite another task's entries or present
   an unsupported conclusion as fact.
9. Never perform work that could damage, destabilize, or disrupt the host
   system. This includes running PoCs or exploits on the host, changing the host
   kernel, modules, sysctls, firewall, mounts, block devices, or services,
   rebooting or shutting down the host, and exhausting host resources. Perform
   any such work only inside a task-owned VM or the official KernelCTF service.
10. Before executing a generated command, PoC, patch, or test procedure, verify
    its exact target, arguments, expected side effects, and containment. Before
    reporting a path, symbol, line, config, diagnostic, result, or impact, verify
    that it exists in the current evidence. Fluent output and pattern matches are
    not findings.

User instructions may change the research goal or authorize an action that a
rule explicitly gates on user approval. They do not waive host-safety rules,
ownership checks, preservation of unrelated work, or higher-priority system and
developer instructions.

## Research quality gates

For vulnerability research, first select the requested mode: discovery, triage,
reproduction, exploitability analysis, or exploit development. Do not silently
advance to a more invasive mode. Define a bounded surface and stopping condition,
then maintain a candidate ledger with the exact location, claim, evidence,
counterevidence, cheapest falsifying test, and status.

A candidate moves through three filters in order: required record schema;
static cross-checks and reproduction readiness; and dynamic reproduction of the
predicted behavior. A rigorous source proof may be marked `SOURCE_CONFIRMED`,
but only matching runtime evidence may be marked `DYNAMIC_CONFIRMED`; track
target reachability and exploitability separately. Neither an LLM assertion,
tool warning, suspicious pattern, nor unexplained crash confirms a
vulnerability. After confirming a root cause, search for structural variants,
but validate every variant independently.

## Mandatory routing

- VM lifecycle, kernel build, guest command, transfer, GDB, or profile task:
  read and follow `agents/vm-operations.md` before acting.
- Any vulnerability discovery, triage, reproduction, validation, exploitability,
  or exploit-development task: first read and follow
  `agents/kernel-research.md`.
- Discovery, source audit, report/patch/suspicious-path triage, static triage,
  candidate falsification, no-candidate pivoting, prior-art review, or variant
  search: also read and follow `agents/kernel-discovery.md`.
- Reproducer construction or reduction, runtime crash triage, KASAN/KCSAN
  validation, dynamic confirmation, or trigger reliability: cumulatively read
  and follow `agents/kernel-discovery.md` and `agents/kernel-reproduction.md`.
- Exploitability analysis or exploit development: cumulatively read and follow
  `agents/kernel-discovery.md`, `agents/kernel-reproduction.md`, and
  `agents/kernel-exploitation.md`.
- KernelCTF target comparison, eligibility, reliability, packaging, evaluation,
  submission, disclosure, or publication: read and follow
  `agents/kernelctf-submission.md` before acting.
- Kernel-research final report, research-artifact preservation, VM cleanup, or
  research termination decision:
  read and follow `agents/reporting-and-cleanup.md` before acting.
- Read every applicable document when conditions overlap. This file defines the
  safety and authorization boundary; routed documents provide the detailed
  procedure within that boundary.
