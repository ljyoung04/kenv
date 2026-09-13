# AGENTS.md — Required rules for `kenv`

These rules apply to every task in `/workspace`. Detailed procedures in
`agents/` become mandatory when their routing condition applies.

## Always required

1. Start every Bash invocation with `source /workspace/scripts/env.sh` before
   using project paths or scripts.
2. Treat `vm.sh` and `kernel.sh` as stateless. Pass `-p <profile>` to profile
   operations and `-p <profile> -v <vm>` to VM operations. Never inherit scope
   from variables, aliases, `envlx`, or earlier commands. For SSH, place `--`
   before the guest command.
3. Name agent-created VMs `<task>_<unix-timestamp>`. Names `a`, `vm`, `vm1`,
   `test`, and `debug` are reserved for the user.
4. Store research code, PoCs, exploits, logs, and notes under
   `$SHARE/<research-name>/`. Transfer files only with `vm.sh scp`; prefix guest
   paths with `vm:`. Never use `--shared`, 9p, virtiofs, or equivalent sharing
   for vulnerability or exploit work.
5. Never modify or invoke `$SCRIPTS/envsetup.sh` or `$SCRIPTS/run-vm.sh`. Never
   read or rely on `$PRJ/reports/`, overwrite unrelated files, edit reference
   PoCs in place, or treat stale agent output as authoritative.
6. Keep execution inside task-owned local VMs or the official KernelCTF service.
   Uploading, submitting, reporting, or publishing requires explicit user
   instruction.
7. Before handoff, record vulnerabilities and useful primitives found during the
   task in `$SHARE/<research-name>/FINDINGS.md` for the next agent. State only
   concise, objective facts: trigger conditions, affected code, observed
   behavior, and supporting artifact paths. Do not include opinions or
   unsupported conclusions.
8. Never perform work that could damage, destabilize, or disrupt the host
   system. This includes running PoCs or exploits on the host, changing the host
   kernel, modules, sysctls, firewall, mounts, block devices, or services,
   rebooting or shutting down the host, and exhausting host resources. Perform
   any such work only inside a task-owned VM or the official KernelCTF service.

## Mandatory routing

- VM lifecycle, kernel build, guest command, transfer, GDB, or profile task:
  read and follow `agents/vm-operations.md` before acting.
- Vulnerability discovery, source audit, reproducer, KASAN validation,
  exploitability analysis, or exploit development: read and follow
  `agents/kernel-research.md` before acting.
- KernelCTF target comparison, eligibility, reliability, packaging, evaluation,
  submission, disclosure, or publication: read and follow
  `agents/kernelctf-submission.md` before acting.
- Final report, artifact preservation, VM cleanup, or termination decision:
  read and follow `agents/reporting-and-cleanup.md` before acting.
- Read every applicable document when conditions overlap. Explicit user
  instructions take precedence over conflicting details.
