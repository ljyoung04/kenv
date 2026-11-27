# Scout pass: reachable surfaces and object maps

Read this when you are a scout or object-map worker for `vuln-discovery`.
The analyst pass reasons over your output, so whatever you omit becomes
its blind spot.
Breadth and exact locations matter more than insight here: record facts
with `path:line`, and leave judgments about bugs to the analyst.

Ground rules:

- Follow root `AGENTS.md` and the Scope section of this skill's `SKILL.md`:
  static only, no build-and-run, no VMs.
- Read `scope.md` first for the revision, source root, config, and threat
  model.
- Write only the file you were assigned. Do not dispatch subagents.
- Cite every location as `path:line` relative to the source root in
  `scope.md` (`net/unix/af_unix.c:1234`, not `af_unix.c:1234`). The
  orchestrator checks citations mechanically, and a bare file name fails.
- Record the exact search commands you ran, so the orchestrator can re-run
  them to measure completeness.
- Start the file with `Produced-by: <model, effort>`.

## Part A — Scout: select reachable surfaces

Goal: within the assigned scope, find code that the attacker defined in
`scope.md` can reach, and rate it on two separate axes.

### A1. Enumerate entry points

Start from interfaces and work inward. Useful starting searches:

```bash
rg -n 'SYSCALL_DEFINE[0-6]\(' <scope>
rg -n '\.(unlocked_ioctl|compat_ioctl|read_iter|write_iter|read|write|mmap|poll|release|open|flush|fasync|splice_read|splice_write|llseek)\s*=' <scope>
rg -n 'struct (proto_ops|proto|net_proto_family) ' <scope>
rg -n '(sock_register|proto_register|genl_register_family|rtnl_register(_many|_module)?|register_pernet_(subsys|device))\(' <scope>
rg -n '\.(setsockopt|getsockopt|sendmsg|recvmsg|ioctl)\s*=' <scope>
rg -n '(timer_setup|hrtimer_(init|setup)|INIT_(DELAYED_)?WORK|call_rcu|kfree_rcu|tasklet_setup)\(' <scope>
```

Include asynchronous contexts that attacker actions arm: timers,
workqueues, RCU callbacks, completion handlers, and softirq paths reachable
through loopback traffic.

### A2. Decide privilege and config gates from code

For each entry point, read the path down to the interesting code and record
every gate with `path:line`:

- `capable()`, `ns_capable()`, `file_ns_capable()`, `sk_net_capable()`,
  `netlink_ns_capable()`, `GENL_ADMIN_PERM` / `GENL_UNS_ADMIN_PERM` flags,
  and capability checks in a socket family's `create` function.
- A namespace-relative check such as `ns_capable(net->user_ns, ...)` is
  attacker-reachable only if `scope.md` says the attacker can create user
  namespaces.
- Sysctls that gate unprivileged use, for example
  `kernel.unprivileged_bpf_disabled`, `vm.unprivileged_userfaultfd`,
  `kernel.perf_event_paranoid`, `kernel.io_uring_disabled`,
  `dev.tty.ldisc_autoload`, `kernel.yama.ptrace_scope`, and the subsystem's
  own.
- Device node permissions in the guest image, and module autoloading
  (`request_module`) when the code is built as a module.
- Config: the controlling `CONFIG_*` is set in the target `.config`, and the
  file is compiled (`obj-$(CONFIG_X)` in the Makefile).

Mark a gate `unknown` when it depends on runtime values you cannot see.
Do not guess.

### A3. Rate and record

Rate the two axes separately. Do not merge them into one score.

- **Reachability:** a concrete entry from low privilege, and its
  prerequisites (capabilities, user namespaces, devices, mounts, network
  state, sysctls).
- **Security relevance:** parses or copies data across a trust boundary;
  manages lifetimes, refcounts, shared state, credentials, sizes, or
  indices; has complex error unwinding, async teardown, lock hand-offs,
  type conversions, or variable-length data.

File size or "it's C" is not a reason to select code. A small adapter that
carries attacker input across a lifetime or privilege boundary is.

Write `exploration/<scope-id>.md`, one record per target:

```text
Target-ID: T-0001
Produced-by: <model, effort>
Owner-scope: <assigned area>
Code: <files, directories, key symbols>
Entry: <attacker-originated entry point>
Config-gates: <CONFIG_* required; set in target .config? y/n>
Privilege-gates: <checks with path:line | none found | unknown>
Reachability: high | medium | low | unknown
Security-relevance: high | medium | low
Boundary: <trust / privilege / lifetime boundary>
Attacker-control: <controllable values and constraints>
Preconditions: <privileges, namespaces, state>
Key objects: <structs whose lifetime or fields the attacker influences>
Dependencies: <callers, callees, structures to read together>
Why-audit: <concrete reason>
Why-not: <reason for lower priority or exclusion>
Leads: <optional, one or two sentences; used only for prioritization>
```

If a bug idea comes up, write one or two sentences under `Leads` and move
on. Do not start deep analysis here. End the file with the excluded and
unreviewed areas of your scope and the reason for each.

## Part B — Object map for one target

Goal: for one selected target, list the subsystem's main objects and every
place they are allocated, made reachable, used, released, and freed. The
analyst can then reason about lifetimes across files without first having
to rediscover them.

### B1. Choose the objects

Map the objects that are created, destroyed, or modified through attacker
actions; carry attacker-controlled fields; or are shared by two or more
entry points or execution contexts. That is usually two to six per target.
Include the containers that make them findable: lists, hash tables, idr,
xarray, rbtree, the fd table, `file->private_data`, `sk_user_data`.

Do not map the kernel-wide life of core objects (`struct file`, `sock`,
`sk_buff`, `task_struct`, `mm_struct`, `cred`, `net`). Record the contract
this subsystem relies on (for example "file pinned by `fdget()` for the
duration of the syscall") and this subsystem's own get/put sites for them.

### B2. Format

Write `objects/<target-id>.md`:

```text
Target-ID: T-0001
Produced-by: <model, effort>
Source root: <path> @ <revision>   (all paths below are relative to it)

## Object: struct foo_ctx
Defined: net/foo/foo.h:42
Allocated from: <kmem_cache "name" + flags (SLAB_TYPESAFE_BY_RCU, SLAB_ACCOUNT, ...) | kmalloc size expression | embedded in <parent>>
Lifetime rule: <refcount field and type; RCU-deferred free?; each lock and the fields it protects; who owns the base reference>
Containers: <where it is published; lookup rule (which lock, or RCU)>

| Kind | Site | Function | Reached from (entry; context) | Locks held | Ref held | Note |
|---|---|---|---|---|---|---|
| ALLOC | net/foo/foo.c:120 | foo_create | socket(AF_FOO); process | — | base ref | kzalloc |
```

Row kinds:

| Kind | Meaning |
|---|---|
| `ALLOC` | Allocation |
| `PUBLISH` | Becomes reachable by other threads or contexts: container insert, `fd_install`, `rcu_assign_pointer`, pointer stored in a shared object |
| `GET` | Reference acquired, including lookup followed by `*_inc_not_zero` |
| `USE` | Field read or write, or the object passed on to another function |
| `PUT` | Reference dropped |
| `UNPUBLISH` | Removed from a container, or a shared pointer cleared |
| `FREE` | Memory released, directly or deferred (`kfree_rcu`, `call_rcu`, a work item) |
| `ASYNC-ARM` / `ASYNC-CANCEL` / `ASYNC-RUN` | A timer, work item, tasklet, RCU callback, or completion that references the object: where it is armed, where it is cancelled (note `_sync` or not), and the callback body |
| `ERR-UNWIND` | Put or free on an error path of an allocation or initialization function |

`Locks held` lists locks taken earlier in the same function, or asserted
(`lockdep_assert_held`, `__must_hold`, a documented rule). Write `caller?`
when a caller may hold a lock you did not trace. `Ref held` says whether
this path holds a counted reference at the site (`y`, `n`, `?`).

Then, for each object:

```text
User-controlled fields:
| Field | Set at (site; source such as copy_from_user / nla_get_* / optval / ioctl arg) | Checked at (site; condition) or "none found" | Read at (sites) |

Concurrency surface: <entry points and contexts that can touch one instance
at the same time, and how an attacker arranges it: two threads on one fd,
sharing through dup/fork/SCM_RIGHTS, close during an operation, a timer or
work item firing>

Attacker operations:
| Operation | Entry | Effect on the object (create / publish / use / modify field / unpublish / put / free) | Privilege |

Searches run:
- `rg -n '<pattern>' <paths>` → <hits>; all mapped | <n> not mapped: <why>

Unresolved: <indirect calls not resolved, macros not expanded, files not read>
```

### B3. Completeness rules

- **The release side is exhaustive.** List every `PUT`, `UNPUBLISH`, `FREE`,
  `ASYNC-*`, and `ERR-UNWIND` site the subsystem has for the object. Search
  for the object's own helpers (`*_put`, `*_release`, `*_destroy`, `*_free`),
  generic ones (`kfree`, `kvfree`, `kmem_cache_free`, `kfree_rcu`,
  `call_rcu`, `refcount_dec_and_test`, `kref_put`, `atomic_dec_and_test`,
  `percpu_ref_kill`, `list_del*`, `hlist_del*`, `idr_remove`, `xa_erase`,
  `rb_erase`), and ops-table callbacks (`.release`, `.destroy`,
  `->sk_destruct`, `.free`). A missed free path is the most expensive
  omission this pass can make, because the analyst's use-after-free
  reasoning starts from the release side.
- **The use side is recorded per function.** For each function that uses the
  object, record its first and last access, and every access that follows a
  lock drop, a sleep, a user copy, a callback, or a handoff to another
  owner. Accesses inside one locked section can be grouped into one row.
- **Resolve indirect calls** through ops tables and callback registration.
  List what you could not resolve under `Unresolved`.
- **Include the error paths** of every allocation and initialization
  function.
- **Record facts, not verdicts.** "No lock held at `net/foo/foo.c:310`" is a
  fact; "race at `net/foo/foo.c:310`" is a verdict. Verdicts in the map
  would anchor the analyst. Put bug ideas in your final message to the
  orchestrator, not in the map; the orchestrator uses them only to order
  work.

### B4. Stopping rule

Stop when every object has rows of each kind, or an explicit
`none found (searches: ...)` or `unresolved (<reason>)`, and every
user-controlled field has a set site and a check entry. Do not analyze
interleavings or arithmetic; that is the analyst's job.

Return to the orchestrator: the objects mapped, the row count per kind, the
unresolved items, and any leads.
