# Reporting, persistence, and cleanup

Read this for kernel-research final reports, research-artifact preservation, VM
cleanup, or research termination.

Continue while technically justified next steps remain within the declared time
and resource budget. Terminate when the requested mode or outcome is complete; a
confirmed duplicate disqualifies a new-vulnerability submission track unless
one-day practice was requested; the required interface or primitive is
unavailable; the candidate is disproved; required access is unavailable; or no
evidence-backed next step remains within the budget. Do not claim general
infeasibility: state the exact configuration, strategies tested, negative
evidence, and uncertainty.

As applicable to the requested mode, the final report records subsystem, exact
revisions/configs, restrictions, dated sources, root cause, lifecycle, trigger,
objects/caches/fields, reproducer, KASAN/serial evidence, reproduction rate,
prior-art and eligibility, primitive chain, mitigations, attempted strategies,
reliability/runtime, result, uncertainties, cleanup state, and exact artifact
paths and SHA-256 values. Mark inapplicable or unperformed stages explicitly;
never imply they ran. Link to complete logs rather than embedding large serial or
KASAN output in the report.

Separate evidence from inference. Format commands as fenced `bash`, logs and
layouts as fenced `text`, and paths in backticks. Format a path and line as
`path:120`.

Before stopping or removing a VM, match the exact profile and VM against the
current task's manifest. For a running VM, also match its `vm.sh ps --json`
entry. For a stopped VM, confirm that it is absent from that output and match
its directory metadata to the manifest. If no manifest exists, preserve the VM
unless ownership can be established from commands and artifacts recorded by the
current task. A name pattern alone is not proof of ownership.

Stop only task-owned VMs and preserve their directories/logs:

```bash
source /workspace/scripts/env.sh
"$SCRIPTS/vm.sh" -p <profile> -v <vm> kill
```

Remove a stopped task-owned VM only after preserving or intentionally
discarding its evidence:

```bash
source /workspace/scripts/env.sh
"$SCRIPTS/vm.sh" -p <profile> -v <vm> rm
```

`kill` and `rm` must reject a live recorded PID that cannot be verified as the
QEMU process for that exact VM. `rm` must also reject a verified live QEMU
process. Never stop or delete unrelated user VMs. Preserve evidence-bearing
directories by default. If confirmed disk pressure requires removal, first copy
the evidence, verify its hashes, record the destination, and report what was
removed. The handoff states which task VMs remain running, stopped, or removed.
