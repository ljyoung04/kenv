# Reporting, persistence, and cleanup

Read this for final reports, artifact preservation, cleanup, or termination.

Continue while technically justified next steps remain. Terminate when the
exploit meets current requirements; a duplicate disqualifies the track; the
interface or primitive is unavailable; multiple distinct strategies establish
infeasibility; the candidate is disproved; or required access is unavailable.

The final report records subsystem, exact revisions/configs, restrictions,
dated sources, root cause, lifecycle, trigger, objects/caches/fields, reproducer,
complete KASAN/serial evidence, reproduction rate, prior-art and eligibility,
primitive chain, mitigations, attempted strategies, reliability/runtime,
result, uncertainties, and exact artifact paths.

Separate evidence from inference. Format commands as fenced `bash`, logs and
layouts as fenced `text`, and paths in backticks. Format lines as `path`:120.

Stop only task-owned VMs and preserve their directories/logs:

```bash
"$SCRIPTS/vm.sh" -p <profile> -v <vm> kill
```

Remove a stopped task-owned VM only after preserving or intentionally
discarding its evidence:

```bash
"$SCRIPTS/vm.sh" -p <profile> -v <vm> rm
```

`rm` must reject a live recorded QEMU PID. Never stop or delete unrelated user
VMs. Preserve evidence-bearing directories unless explicitly instructed or
disk pressure requires cleanup after copying evidence.
