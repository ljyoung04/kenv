# BPF

## 선정 근거

- syzbot 350건, Linux CNA CVE 164건, 공개 kernelCTF 7건.
- verifier의 추상 상태와 runtime/JIT 의미 차이, map/link의 복잡한 수명주기가 주요 결함원이다.
- 최신 COS target에서는 unprivileged eBPF가 제한될 가능성이 높다. 먼저 runtime sysctl과 config를 확인하고, 비권한 classic BPF socket-filter 경로를 우선한다.

## 주요 객체

| 객체 | 역할 |
|---|---|
| `struct bpf_prog` | 검증·JIT된 프로그램 |
| `struct bpf_map` | map 공통 header와 refcount |
| `struct bpf_link` | 프로그램 attachment 수명주기 |
| `struct bpf_verifier_env` | verifier 전체 분석 상태 |
| `struct bpf_verifier_state` | 분기별 register/stack 추상 상태 |
| `struct bpf_insn` | BPF instruction |
| `struct sk_filter` | socket에 연결된 classic/eBPF filter |

## 엔트리 포인트

- `bpf()` commands: `BPF_PROG_LOAD`, `BPF_MAP_*`, `BPF_LINK_*` — 허용 여부 확인
- `setsockopt(SO_ATTACH_FILTER)` / `SO_ATTACH_BPF`
- `setsockopt(SO_DETACH_FILTER)`
- `seccomp()` classic BPF filter
- `perf_event_open()` 기반 attachment — sysctl 제한 확인
- TC/XDP/netlink attachment — capability 제한 확인

## 우선 조사 경계

- classic-BPF-to-eBPF 변환과 JIT
- socket filter attach/detach 및 socket close race
- verifier state pruning, scalar bounds, reference tracking
- map-in-map, ring buffer, local storage의 teardown
- 제외: `CAP_BPF`, `CAP_SYS_ADMIN`, user namespace로만 도달 가능한 경로

## 출처

- <https://syzkaller.appspot.com/upstream/s/bpf>
- <https://github.com/CVEProject/cvelistV5>
- <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>

