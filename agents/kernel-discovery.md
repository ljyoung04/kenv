# Kernel vulnerability discovery and static validation

Read this after [`kernel-research.md`](kernel-research.md) for discovery, source
audit, static triage, candidate falsification, no-candidate pivoting, prior-art
review, or variant search. Runtime experiments belong in
[`kernel-reproduction.md`](kernel-reproduction.md).

## Select a bounded surface

Do not begin with an unguided whole-kernel audit. Choose a subsystem, interface,
object family, patch series, or previously confirmed bug pattern; state why it
is promising, define the files/functions and entry points in scope, and set a
stopping condition. Expand only after the initial scope has been reasonably
explored.

Useful starting points include:

- recent `git log`, `git diff`, `git show`, and `git blame` changes that alter
  lifetime, locking, parsing, or reachable interfaces;
- syscalls, ioctls, netlink, procfs, sysfs, mmap, file-descriptor operations,
  and device nodes reachable under the target permissions;
- shared objects with multiple owners, error exits, reference counting, RCU,
  workqueues, timers, cancellation, or namespace teardown;
- user-controlled lengths, indexes, offsets, flags, arithmetic, conversions,
  and allocation sizes; and
- neighboring implementations with different locking, validation, or cleanup.

Prefer candidates with verified reachability and plausible memory-corruption or
local-privilege-escalation impact under the actual target configuration.

## Build invariant-based candidates

For each object or interface, model:

1. **Creation:** allocation, cache/size, initialization, and partial states.
2. **Exposure:** publication, shared-structure insertion, fd handoff, and
   ownership or reference transfer.
3. **Use:** readers/writers, user-controlled state, locks, RCU regions,
   callbacks, timers, and work execution.
4. **Withdrawal:** unlink, close/release, cancellation, shutdown, namespace
   teardown, and reference release.
5. **Destruction:** final put, grace period, free, error unwind, and aliases that
   may remain.

Trace normal, error, cancellation, and teardown paths. Consider UAF, double free,
refcount errors, races, OOB access, overflow/truncation, uninitialized use, type
confusion, stale pointers, incorrect locking, and missing validation. For a race,
name the exact competing paths, required interleaving, locks/references held by
each path, and why overlap is possible. Record every candidate using the shared
schema and statuses in [`kernel-research.md`](kernel-research.md).

## Static validation, falsification, and reproduction readiness

Apply these pre-reproduction gates in order:

1. **Schema:** do not advance a candidate missing a precise location, evidence,
   counterargument, and verification method.
2. **Static cross-check:** verify symbols and excerpts in the current tree;
   follow callers/callees; resolve definitions and build/config guards; identify
   required runtime state and caller permissions; and check locks, refcounts,
   RCU, and cleanup symmetry. Interface existence is not proof of caller access,
   and runtime facts remain unverified until observed.
3. **Reproduction readiness:** define the minimal trigger, exact target and
   credentials, expected observation, falsifying outcome, instrumentation,
   timeout, resource bound, and containment before starting a VM experiment.

Use source queries and small scripts to check machine-verifiable claims before
spending manual review on them. Use Smatch/Sparse or Coccinelle only when they
answer a stated source question. A tool warning does not prove a root cause, and
a clean static-analysis run does not prove absence.

Mark `SOURCE_CONFIRMED` only when the source supplies a complete proof, such as
concrete bounds and inputs for an OOB access, a demonstrated arithmetic overflow,
or a fully established lifetime/interleaving violation. Otherwise keep the
candidate at the strongest justified hypothesis status.

Advance to dynamic reproduction when a source-supported claim has a plausibly
reachable trigger and the experiment can discriminate between the claim and its
main counterargument. A `SOURCE_CONFIRMED` bug whose target path is unavailable
retains its source status but is not ready for target reproduction. Otherwise
refine, block, refute, or defer the candidate.

### When no candidate survives

Do not repeatedly reread the same functions or broaden the scope without a new
question. Record each inspected surface in `coverage.md` with entry points,
lifecycle paths, commits and analogues checked, unresolved facts, result, and
next pivot. Then apply this bounded sequence:

1. **Complete lifecycle coverage:** inspect any unreviewed creation, exposure,
   use, withdrawal, destruction, error, cancellation, or teardown path for the
   same object. Stop when each relevant path is reviewed or marked unavailable.
2. **Revisit change history:** inspect recent modifications, blamed lines,
   reverted or partial fixes, stable backports, and changed assumptions. Continue
   only if a commit introduces a new invariant, boundary, or reachable path.
3. **Compare structural analogues:** find implementations using the same object,
   operations table, callback sequence, helpers, or lifetime pattern. Compare
   their locking, refcounting, validation, and cleanup rather than their names.
4. **Resolve a reachability uncertainty:** when source evidence is promising but
   call-path coverage is uncertain, plan the smallest KCOV, ftrace, GDB, or
   assertion experiment. Execute it only under
   [`kernel-reproduction.md`](kernel-reproduction.md).
5. **Pivot deliberately:** if lifecycle coverage is complete and neither change
   history nor at least one analogue produces a new evidence-backed hypothesis,
   record `NO_CONFIRMED_CANDIDATE_IN_SCOPE` as the surface outcome in
   `coverage.md`; it is not a candidate root-cause status. Rank the next bounded
   surface by target reachability, change density, lifecycle/concurrency
   complexity, user control, and plausible impact, then start a new ledger entry.

Every expansion names the new dimension and its stopping condition. Do not reopen
a closed surface without new code, target facts, runtime evidence, or a distinct
hypothesis.

## Check prior art and search for variants

Do a lightweight duplicate and fixed-version check before investing heavily.
After stable reproduction and before substantial exploitation, search syzbot,
syzkaller, lore/kernel lists, mainline/stable Git, CVEs/advisories, public PoCs,
subsystem trackers, and KernelCTF submissions. Compare root cause, object
lifecycle, source paths, trigger, stacks, affected versions, and fixing commits,
not just crash text or CVE names. Record exact queries, direct links, retrieval
dates, version boundaries, and reasoning. Classify the result as duplicate/fixed,
public one-day, apparently unreported, or uncertain; absence of a result does not
prove novelty.

Once one root cause is `SOURCE_CONFIRMED` or `DYNAMIC_CONFIRMED`, derive a
structural signature: the violated invariant, helper/callback relationship,
lifetime transition, missing lock/reference/validation, and relevant object
fields. Search neighboring code, other implementations, related drivers, and
affected branches for semantic variants even when names and syntax differ. LLMs,
Coccinelle, and source queries may generate candidates, but each variant receives
its own ledger entry and must pass the static gate before `SOURCE_CONFIRMED` and
the reproduction gate before `DYNAMIC_CONFIRMED`. Do not inherit reachability,
severity, or confirmation from the original bug.
