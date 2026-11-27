# Analyst pass: lifetime, concurrency, and bounds

Read this when you are an analyst or a re-verifier for `vuln-discovery`. You
run on the strongest model because this is where kernel bugs are found or
missed. The free is often in one file, the use in another, and the lock that
should order them in a third. The bug is the missing relation between them,
and reasoning one function at a time does not see it. Track each object's
state as it changes across functions, files, and execution contexts until
every relevant path is accounted for.

Ground rules:

- Follow root `AGENTS.md` and these sections of this skill's `SKILL.md`:
  Scope, Required falsification, Candidate record. Static only.
- Write only your assigned file. Do not dispatch subagents.
- Cite every location as `path:line` relative to the source root in
  `scope.md`.
- Start the file with `Produced-by: <model, effort>`.

## Inputs and blindness

Read `scope.md` (revision, config, threat model), your target's entry in
`targets.md`, `objects/<target-id>.md`, and the source at the pinned
revision.

Until you have written your own verdicts, do not read other analysis
records for this target, other research directories' conclusions about it,
or scout leads. Once your verdicts are written, read them and record every
disagreement and how you resolved it. An earlier conclusion read first
tends to become your conclusion. Read afterwards, it is a useful
cross-check.

As a re-verifier, you get a claim to test instead of a target to explore.
Use the same procedure. Step 6 covers how to test an earlier guard.

If `targets.md` marks the map `INCOMPLETE`, rebuild the listed parts first.

## Step 1 — Rebuild the release side

The map came from a cheaper model, so do not rely on it until you have
checked it. For each object you reason about:

1. Re-run the map's searches, and add your own for that object's release
   paths: helpers, ops-table callbacks, container removal, async cancel,
   error unwinding, and module or netns exit.
2. Open every `PUT`, `UNPUBLISH`, `FREE`, `ASYNC-*`, and `ERR-UNWIND` row at
   its cited line.
3. Record added, corrected, and missing rows under `Inventory corrections`.

## Step 2 — Model what the attacker can do

For each object:

- Write its state machine. Give the states (for example allocated →
  initialized → published → in use → unpublished or dying → freed, plus
  subsystem states such as connected or closing) and the transitions, each
  with `path:line` and the entry that triggers it.
- Mark which transitions the attacker can trigger repeatedly, out of the
  intended order, from two threads or processes at once, or against an
  asynchronous context. Two threads can share one fd. Processes can share
  objects through `dup`, `fork`, or `SCM_RIGHTS`. Close can run during an
  operation. Asynchronous contexts include timers, work items, RCU
  callbacks, softirq, and completions.
- Note the timing control the threat model allows: thread count, CPU
  pinning, blocking on user-memory faults (FUSE or userfaultfd only if
  `scope.md` allows them), large copies, and signals. A narrow window makes
  a candidate less practical. It is not a reason to reject it.

## Step 3 — Lifetime and concurrency (use-after-free, double free)

### 3.1 Justify every use

For each `USE` reachable from an attacker entry or an asynchronous context,
name what keeps the object alive at that point, and cite the evidence:

| Justification | What must hold |
|---|---|
| Held reference | Acquired before the use and released after it, at cited sites. A lookup acquires with `*_inc_not_zero`, or under the lock the free path takes, so it cannot revive a dying object |
| Lock | The free path takes the same lock and unpublishes the object, or marks it dead, under that lock before freeing. The use path holds the lock from lookup to last access, or revalidates after re-acquiring it |
| RCU | The use stays inside one read-side section from lookup to last access. The free waits a grace period after unpublish (`kfree_rcu`, `call_rcu`, `synchronize_rcu`). For `SLAB_TYPESAFE_BY_RCU`, identity is re-checked after taking a reference |
| Owner pin | An owner keeps the object alive, for example the file pinned by `fdget()` for the syscall. Show why no other entry (close, unlink, disconnect, netns exit) can release that owner meanwhile |
| Teardown ordering | Teardown waits for this user (`cancel_work_sync`, `timer_delete_sync` / `timer_shutdown_sync`, `flush_workqueue`, a completion, a refcount drain), and the user cannot re-arm after the wait |

A use with no justification you can cite is a candidate. A use that has a
justification is not safe yet; attack the justification. Does it cover
every path to the use, including error and retry paths, the window between
lookup and get, and the window between unlock and relock? Is the free path
guaranteed to observe it?

### 3.2 Relate every free to every use

This table is required. The most common way to miss a use-after-free is to
find both the free and the use and never connect them.

```text
| Free-side site (F) | Use site (U) | Can the attacker make them overlap? How? | What orders U's last access before F, or keeps them apart (mechanism, path:line) | Result |
```

Add a row for every F × U pair the attacker can trigger from different
threads or contexts. `none found` in the ordering column makes the row a
candidate. When a pair is ruled out because one side is unreachable, say
so and cite the gate.

### 3.3 Balance references across functions

For every get, find the put on every path, including error paths. Record
the convention whenever a function consumes (takes over) a reference or
only borrows it. An extra put frees too early, which is a use-after-free. A
missing put leaks the object; record it at lower priority.

### 3.4 Relations worth checking

These are common ways the ordering breaks. Use them as prompts for the
table above, not as a checklist to pattern-match.

- Lookup and use without a reference, or `refcount_inc` on a count that may
  already be zero.
- A lock dropped, a sleep, or a user copy between check and use, with no
  revalidation afterwards.
- An object published before it is fully initialized, freed on an error
  path while still published, or unpublished only after it is freed.
- Teardown that does not wait for asynchronous users: a non-sync cancel, a
  work item or timer that re-arms itself, or an RCU callback or completion
  still pending at free.
- Two paths that each believe they hold the last reference: release against
  an error path, or a timeout against a completion.
- Use after an ownership handoff (`fd_install`, queueing to a worker,
  attaching to another object) without holding a reference of its own.
- Iteration over a container while entries are freed, or a lock dropped in
  the middle of an iteration.
- A child object or callback that outlives the owner whose release frees
  it.

### 3.5 Interleaving

For each surviving lifetime candidate, write the concrete interleaving:

```text
| Step | Thread A (context) | Thread B (context) | Locks held; object state; refcount |
|---|---|---|---|
| 1 | foo_ioctl() finds ctx under rcu_read_lock(), takes no reference — net/foo/foo.c:310 | | rcu; published; 1 |
| 2 | rcu_read_unlock(), then copy_from_user() may sleep — net/foo/foo.c:318 | | none; published; 1 |
| 3 | | foo_release() unpublishes ctx — net/foo/foo.c:402 | ctx->lock; unpublished; 1 |
| 4 | | foo_put() drops the last reference and frees — net/foo/foo.c:415 | none; freed; 0 |
| 5 | reads ctx->buf — net/foo/foo.c:322 (first invalid access) | | none; freed |
```

Check that each step is allowed. No lock held by one side may block the
other side's step, sleeping and atomic-context rules must hold, and the
window must exist in the code; say what fills it. End with the first
invalid access: function, `path:line`, read or write, and field and offset
if known. Dynamic validation matches its sanitizer report against this.

## Step 4 — Untrusted values (out-of-bounds, integer errors)

### 4.1 Sources

User copies (`copy_from_user`, `get_user`, `strncpy_from_user`,
`memdup_user`), ioctl arguments, socket option values and lengths,
`msghdr` fields (iov, `msg_control`, name length), netlink attributes,
io_uring SQE fields, sysfs and procfs writes, file contents or filesystem
metadata the kernel parses, packet payloads, and values stored earlier in
objects.

For netlink, the check may live in the attribute policy (`nla_policy`
types and lengths, `NLA_POLICY_RANGE`, `NLA_POLICY_MAX`), possibly in
another file. Read the policy.

### 4.2 Follow values across functions, files, and time

Trace each value through assignments, struct fields, parameters, and return
values. A value stored in an object (by setsockopt, an ioctl, or a
configuration message) is still attacker-controlled when another entry
reads it later. Trace it to every later reader, and check that every writer
validates it, not only the first writer you found.

### 4.3 Sinks

- Array and pointer indexing
- Lengths for `memcpy`, `memmove`, `memset`, `copy_to_user`, and
  `copy_from_user`
- Lengths and offsets for `skb_put`, `skb_pull`, `skb_push`, and
  `skb_copy_bits`
- Allocation size arithmetic and loop bounds
- Bit-operation indices and shift counts
- Page and offset computations

### 4.4 Test every check on the path

For each source → sink path, list every check, then ask:

- Is the bound the real size of the buffer at the sink? Find where that
  buffer was allocated, possibly in another file, and with what size.
- Do the types allow a bypass? Signed and unsigned mixing lets a negative
  value pass `<`. Truncation (`u32` → `u16`) and overflow in `a + b` or
  `n * size` can happen before the check. Also check `<=` against `<`.
- Can the value or the bound change after the check? Look for a double
  fetch from user memory, or a concurrent setter that updates a stored
  length or replaces a buffer without the lock the reader holds. This is
  where bounds and concurrency meet.
- Does every entry that reaches the sink perform the check? Look at the
  compat path, other ioctl commands, netlink versus sockopt, and other
  message types.
- In nested length or TLV parsing, can a remaining-length subtraction
  underflow? Are `skb` linear-data assumptions backed by
  `pskb_may_pull()`?

### 4.5 Value flow

For each surviving bounds candidate, write the flow and a concrete value:

```text
Source: net/foo/foo_nl.c:205  idx = nla_get_u32(tb[FOO_ATTR_IDX])   (u32; attacker: any value)
Policy: net/foo/foo_nl.c:40   [FOO_ATTR_IDX] = { .type = NLA_U32 }   no range
Check:  net/foo/foo_nl.c:207  if (idx > FOO_NSLOTS) return -EINVAL;  allows idx == FOO_NSLOTS
Flow:   net/foo/foo_nl.c:210  ctx->cur = idx;   stored; read later by foo_timer_fn()
Sink:   net/foo/foo.c:520     ctx->slots[ctx->cur] = val;   slots[] has FOO_NSLOTS entries (net/foo/foo.h:30)
Value:  idx = FOO_NSLOTS passes the check and writes one element past the end of slots[]
```

## Step 5 — Verify API contracts in the tree

When a conclusion depends on what an API guarantees, read its definition or
kernel-doc in the pinned tree and cite it. Semantics change between
releases, and a contract remembered wrongly leads to wrong verdicts in both
directions. These contracts often decide a verdict:

- `cancel_work` versus `cancel_work_sync`
- `del_timer` / `timer_delete` versus `timer_delete_sync` /
  `timer_shutdown_sync`
- `refcount_inc` versus `refcount_inc_not_zero`
- `list_del` versus `list_del_rcu`, and `kfree` versus `kfree_rcu`
- `fdget` (borrowed) versus `fget` (counted)
- `fd_install`, after which other threads can see the file
- `SLAB_TYPESAFE_BY_RCU`, where memory can be reused for a new object of
  the same type inside a read-side section

## Step 6 — Falsify, decide, stop

- Apply the Required falsification questions in `SKILL.md` to every
  hypothesis.
- **Answer the decisive question.** Each hypothesis has one fact that
  settles it, for example "does every caller of foo_use() hold ctx->lock
  across the access?". Keep the status `HYPOTHESIS` until that fact is
  answered from source, and record the question, the answer, and the
  evidence. If the answer needs code or config you do not have, use
  `NEEDS_CONTEXT` and name the missing input.
- **Priors are not evidence.** "Mature code", "identical to another tree",
  "heavily fuzzed", "would have been found", and "unlikely" can order your
  work. They cannot reject a candidate or support one.
- **Eligibility is not a technical verdict.** A valid defect that is out of
  a program's scope keeps its technical status. Eligibility goes in its own
  field.
- **The bar for `SOURCE_CONFIRMED`:**
  - Lifetime or race: F and U at `path:line`, both reachable under the
    threat model and config; a relation-table row with no ordering
    mechanism; every justification from 3.1 checked; and an interleaving
    whose every step is permitted.
  - Bounds or integer: a source → sink value flow with every check listed,
    and a concrete value that passes all of them and exceeds the real
    bound.

  Anything less stays `HYPOTHESIS`.
- **Other defect classes.** Record uninitialized memory, info leaks, type
  confusion, and missing permission checks you come across, held to the
  same evidence bar. Do not drop them, but do not chase them at the expense
  of the two primary questions.
- **Re-verifying a `REJECTED`.** After writing your own verdict, test the
  earlier guard directly. Is it present at the cited location in this
  revision? Does it cover every path to the use, including error paths,
  async paths, and alternate entries?
- **Stop the target** when all four hold: every release-side site of every
  main object appears in the relation table; every attacker-reachable use
  has a justification or a candidate; every user-controlled field has a
  value flow or a recorded check; and every candidate has a status.

## Output

Write the assigned file (`analysis/<target-id>.md`, or
`reverify/<original-id>.md` for a re-verifier) in this order:

1. Header: Target-ID, Produced-by (model, effort), revision and config, and
   the object map used (path @ SHA-256)
2. Inventory corrections
3. State machine for each object
4. Free/use relation tables
5. Value flows
6. Candidate records in the `SKILL.md` format, including rejected ones
7. Coverage for each object: release-side sites analyzed out of the total,
   uses justified, user-controlled fields traced, and what was left and why
8. Disagreements with earlier records, read after your verdicts

Return to the orchestrator: Candidate-IDs with status and decisive
question, inventory corrections, and coverage gaps.
