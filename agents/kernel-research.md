# Kernel vulnerability research and exploit development

Read this for vulnerability discovery, source analysis, reproduction, KASAN,
exploitability analysis, or exploit development.

## Candidate analysis

1. Record exact revision, config, architecture, credentials, capabilities,
   namespaces, runtime restrictions, and reachable interfaces.
2. Trace allocation, initialization, publication, ownership transfer,
   concurrent use, withdrawal, destruction, error unwinding, refcounts, RCU,
   workqueues, timers, cancellation, file descriptors, namespace teardown, and
   lock ordering.
3. Trace user-controlled sizes, indexes, offsets, flags, conversions, syscalls,
   ioctls, netlink, procfs, sysfs, and mmap interactions.
4. Consider UAF, double free, refcount errors, races, OOB access, overflow or
   truncation, uninitialized use, type confusion, stale pointers, incorrect
   locking, and missing validation.
5. Document the violated invariant, vulnerable object/cache, call path,
   requirements, and benign alternatives. Pattern hits alone are insufficient.

Prefer reachable candidates with realistic memory-corruption or LPE impact
under the actual target configuration.

## Reproduction and prior-art checks

Create `$SHARE/<research-name>/` with `README.md`, sources, `Makefile`, `logs/`,
and `artifacts/`. Start a timestamped `kasan` VM without `--shared`; transfer
with `vm.sh scp`. Run bounded repeated trials and fresh boots where useful.
Preserve kernel/config identity, commands, exit status, complete serial/KASAN
output, and reproduction rate. Reduce the trigger without changing its report,
and confirm the diagnostic matches the predicted lifecycle.

Implement `--vuln-trigger` early so the underlying bug can be tested separately
from the full LPE chain and unnecessary KASLR work.

After stable reproduction and before substantial exploitation work, search
syzbot, syzkaller, lore/kernel lists, mainline/stable Git, CVEs/advisories,
public PoCs, subsystem trackers, and KernelCTF submissions. Compare root cause,
lifecycle, stack, trigger, and fixes. Classify as duplicate/fixed, public
one-day, apparently unreported, or uncertain. Record queries, links, dates, and
reasoning. Absence of a CVE does not prove novelty.

## Exploitability and development

Determine allocation size/cache, lifetime, attacker control, free timing, and
repeatability. Evaluate allocator/control-flow hardening, SMEP, SMAP, KPTI,
KASLR, and replacement objects. Build and validate the chain through reclaim or
overlap, disclosure, read/write, privilege change, and flag retrieval. Test
victims against the actual config and permissions.

Use `$SHARE/kernel-research/libxdk` for KASLR-base acquisition unless instructed
otherwise; never hard-code a base from one boot. Move to a new timestamped
`kernelctf` VM only after confirming root cause, a stable KASAN trigger,
eligibility, and a plausible chain. Copy reference PoCs before adapting them.

Separate trigger, grooming, spraying, cross-cache, leak, corruption, and
escalation stages. Explain constants, objects, caches, fields, fake structures,
offsets, synchronization, raced paths, affinity, limits, and syscall side
effects. When an approach fails, try technically distinct instrumentation,
scheduling, grooming, reclaim objects, primitive conversions, version checks,
or GDB validation while evidence supports further work.

