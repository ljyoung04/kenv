# KernelCTF target, eligibility, and submission

Read this for KernelCTF target comparison, eligibility, reliability, packaging,
evaluation, submission, disclosure, or publication.

Reopen the [official rules](https://google.github.io/security-research/kernelctf/rules.html)
at the start of each KernelCTF task. Follow active-target/configuration links and
record retrieval date and sources. If unavailable, mark current status
unverified. Current official sources override this snapshot.

The snapshot checked 2026-09-07, effective 2026-09-04, specified
`hardened-v1-7.x` on Linux 7.2-rc5 x86_64, with kCFI + IBT,
`SLAB_VIRTUAL=y`, `KMALLOC_PARTITION_TYPED=y`, `SLAB_MERGE_DEFAULT=n`, and
disabled io_uring, user namespaces, TLS, crypto user AEAD, and AF_UNIX OOB.
Unprivileged BPF defaulted off. The underlying bug also had to trigger on the
applicable LTS 6.12 target.

Verify compiled support, runtime enablement, and caller permission separately.
Do not assume nftables status; do not interpret the BPF default as all BPF being
absent or disabled user namespaces as all `unshare` being absent.

## Eligibility and reliability

Check disclosure, syzbot, mainline fixes, stable backports, and previous
submissions. Evaluate duplicates by root cause and fixing commits, not CVE.
Stop a new-vulnerability submission track on a confirmed disqualifying report,
fix, or duplicate unless one-day practice was requested.

Support `--vuln-trigger` on the required LTS. Measure at least 20 independent
exploit runs across boots and record success, failure, runtime, and causes. The
2026-09-07 snapshot required at least 70% success within five minutes and
scored reliability and speed; recheck before relying on those values. Do not
consume limited official attempts until local parity, LTS triggering, packaging,
and measurements are reviewed.

## Packaging

Preserve the exact evaluated archive and hash. Published layout:

```text
pocs/linux/kernelctf/<cve>_<targets>/
├── original.tar.gz
├── metadata.json
├── docs/vulnerability.md
├── docs/exploit.md
└── exploit/hardened-v1-7.x/
    ├── exploit.c
    ├── exploit
    └── Makefile
```

Document trigger requirements, introducing/fixing commits, versions, subsystem,
root cause, blockable interfaces, exploitation stages, objects/caches/fields,
constants, ROP, fake structures, threads, environment, namespaces, and measured
stability. Preparing and locally testing files is authorized by a research
request. Evaluation uploads, flag/form submission, emails, or publication PRs
require explicit user instruction.

