## 푸는 순서

### 1. K3RN3LCTF - Easy kernel is still kernel right?

kernel ROP, KASLR, canary, KPTI 기본기

### 2. UIUCTF 2025 - Baby Kernel

UAF -> tty_struct reclaim

kernel heap exploit 입문

### 3. TsukuCTF 2025 - xcache

double free

slub freelist 구조와 freelist posioning

### 4. DiceCTF 2021 - hashbrown

race condition

UAF

userfaultfd를 이용한 race 제어

pipe_buffer

page-cache overwrite

deterministic exploit과 race exploit 차이 체감하기

### 5. HITCON 2022 - Fourchain - Kernel

race + UAF

msg_msg

pipe_buffer

sk_buff

DirtyCred

kernelROP

하나의 버그에서 여러 커널 객체들과 exploitation path를 설계하는 연습

### 6. D^3CTF 2025 - d3kheap2

refcount buf

double free

cross-cache

msg_msg <-> pipe_buffer

Dirty Pipe 계열

slub object 단위 사고에서 slab/page 단위 사고로 넘어가기

### 7. hxp CTF 2021 - trusty user diary

get_user_pages()

FOLL_WRITE

COW bypass

pinned page

page-cache corruption

힙과 완전히 다른 vm/page subsystem exploitation 경험

### 8. SECCON CTF 2022 - babypf

ebpf verifier

range analysis bug

ebpf stack corruption

AAR/AAW

verifier가 이 값은 안전하다고 잘못 판단하게 만드는 원리 익히기

### 9. KalmarCTF 2024 - msrable

MSR

LSTAR

FMASK

syscall entry

CR4

SMEP/SMAP 관련 흐름

KPTI return

allocator와 관계없는 CPU architectural state 기반 익스플로잇 경험

### 10. HITCON 2024 - Seccomp Hell

x86 privilege level

CPL3 -> CPL0

LDT

call gate

cred

seccomp patch

UAF -> spray 같은 정형화된 풀이가 아니라 x86/linux 내부 메커니즘 자체를 공격하는 사고방식

### 11. N1CTF 2024 - heap_master

cross-cache UAF

struct file

PTE corruption

Dirty Page 계열

physical-memory-access 

kernel text patch

현대 커널 익스플로잇에서 중요한 page-table primitive까지 연결하기

### 12. DiceCTF 2026 - cornelslop

RCU UAF race

rcu lifetime

rcu callback hijack

cross-cache pipe reclaim

physical/QEMU primitive까지 연결

마지막 종합 문제, 단순 kfree UAF와 다른 asynchronous lifetime buf 익히기

