# KernelCTF target, eligibility, and submission

Read this for KernelCTF target comparison, eligibility, reliability, packaging,
evaluation, submission, disclosure, or publication.

Reopen the [official rules](https://google.github.io/security-research/kernelctf/rules.html)
at the start of each KernelCTF task. Follow active-target/configuration links and
record the UTC retrieval time, direct URLs, target revision, config and image
hashes, and any effective date in the research manifest. If a source is
unavailable, mark current status unverified. Current official sources always
override the historical snapshot below.

The following is historical context, not evidence of the current target. The
snapshot checked 2026-09-07, effective 2026-09-04, specified
`hardened-v1-7.x` on Linux 7.2-rc5 x86_64, with kCFI + IBT,
`SLAB_VIRTUAL=y`, `KMALLOC_PARTITION_TYPED=y`, `SLAB_MERGE_DEFAULT=n`, and
disabled io_uring, user namespaces, TLS, crypto user AEAD, and AF_UNIX OOB.
Unprivileged BPF defaulted off. With `--vuln-trigger`, the underlying bug also
had to crash the system on the applicable LTS 6.12 target.

Verify compiled support, runtime enablement, and caller permission separately.
Do not assume nftables status; do not interpret the BPF default as all BPF being
absent or disabled user namespaces as all `unshare` being absent.

## Eligibility and reliability

Check disclosure, syzbot, mainline fixes, stable backports, and previous
submissions. Evaluate duplicates by root cause and fixing commits, not CVE.
Treat eligibility claims copied into this file as historical until verified
against the current official rules. Stop a new-vulnerability submission track
on a confirmed disqualifying report, fix, or duplicate unless one-day practice
was requested.

Support `--vuln-trigger` on the required LTS and follow the current official
reliability method. Until a stricter current method is verified, use a local
baseline of at least 20 independent exploit runs across at least two fresh
boots. Use a declared per-run timeout and identical launch conditions; record
boot identity, success, failure, runtime, and cause. The 2026-09-07 snapshot
required at least 70% success within five minutes and scored reliability and
speed; this is historical until rechecked. Do not consume a limited official
attempt until local parity, LTS triggering, packaging, and measurements are
reviewed and the user explicitly authorizes that attempt.

## Packaging

Preserve the exact evaluated archive and hash. The historical layout pattern
was the following; recheck the current rules before packaging:

```text
pocs/linux/kernelctf/<cve>_<targets>/
├── original.tar.gz
├── metadata.json
├── docs/vulnerability.md
├── docs/exploit.md
└── exploit/<target>/
    ├── exploit.c
    ├── exploit
    └── Makefile
```

Before a CVE exists, use `unassigned_<research-name>` for local staging and
rename it only when the current publication rules provide an identifier. Define
the contents and provenance of `original.tar.gz`, create archives
deterministically where the accepted format permits it, and record SHA-256
values for the archive, source, binary, and metadata.

Document trigger requirements, introducing/fixing commits, versions, subsystem,
root cause, blockable interfaces, exploitation stages, objects/caches/fields,
constants, ROP, fake structures, threads, environment, namespaces, and measured
stability. Before any external action, inspect the package for credentials,
tokens, flags, private host paths, unrelated artifacts, and unlicensed material.
Preparing and locally testing files is authorized by a research request.
Evaluation uploads, flag/form submission, emails, or publication PRs require a
separate explicit user instruction naming the artifact, destination, and action.

