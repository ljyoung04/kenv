# Kernel dynamic reproduction and confirmation

Read this after [`kernel-research.md`](kernel-research.md) and
[`kernel-discovery.md`](kernel-discovery.md) for reproducer construction or
reduction, runtime crash triage, KASAN/KCSAN validation, dynamic confirmation, or
trigger reliability. Also follow [`vm-operations.md`](vm-operations.md).

## Readiness gate

Before running a dynamic experiment, pass the
[reproduction-readiness gate](kernel-discovery.md#static-validation-falsification-and-reproduction-readiness).
Return to static validation if the experiment cannot discriminate the claim
from its counterargument.

## Run the experiment

Start a timestamped VM using a verified KASAN profile, without `--shared`,
record its ownership in `MANIFEST.md`, and transfer only with `vm.sh scp`. Set
the trial count, per-run timeout, and resource budget before repeated runs.
Preserve exact commands, exit status, boot identity, complete per-boot
serial/KASAN/KCSAN logs, and numerator/denominator reproduction rates. Use fresh
boots when state can affect results.

Use syzkaller/KCOV, KASAN, KCSAN, GDB, ftrace, or focused runtime assertions only
when they test the predicted path, state, or interleaving. A clean dynamic run
does not prove absence unless the experiment demonstrably exercised the necessary
path and discriminated the main counterargument.

Implement `--vuln-trigger` early and keep it independent of grooming, KASLR-base
acquisition, and privilege escalation. Document required credentials,
capabilities, namespaces, expected timeout and diagnostic, and ordinary
non-reserved exit codes. A deliberate crash counts as success only when the
contract says so.

Reduce the reproducer while preserving the same root cause and diagnostic.
Confirm that allocation, free, and use stacks, object type/cache, address
relationships, and interleaving match the lifecycle model. An unexplained crash
does not pass the reproduction gate.

## Interpret the result

Classify a failed dynamic test as `UNREACHABLE`, `INVARIANT_PRESERVED`,
`TRIGGER_NOT_EXERCISED`, `SCHEDULE_NOT_ACHIEVED`, `DETECTION_GAP`, or
`ENVIRONMENT_MISMATCH`. Record the evidence and disproven assumption. A failed
test does not refute a `SOURCE_CONFIRMED` root cause unless it disproves part of
the source proof; it may instead establish target unreachability or a detection
gap. Retry only with a technically distinct experiment or new evidence.

Mark `DYNAMIC_CONFIRMED` only when the observed state or diagnostic matches the
predicted root cause. Preserve `SOURCE_CONFIRMED` when source proof is complete
but runtime confirmation is absent, unnecessary for the requested mode, or
blocked by the target environment. Update `candidates.md`, `coverage.md`, and the
supporting artifact hashes after every decisive experiment.

After stable reproduction, complete the discovery document's
[prior-art and variant checks](kernel-discovery.md#check-prior-art-and-search-for-variants)
before substantial exploit development.
