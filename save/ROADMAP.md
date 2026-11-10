# Kernel Exploit Dojo Roadmap

이 로드맵의 목표는 단순히 CTF 문제를 많이 푸는 것이 아닌, 처음 보는 커널 소스에서 취약점을 찾고, 익스플로잇 가능성을 평가한 뒤 실제 익스플로잇까지 개발하는 능력을 기르는 것이다.

## STAGE 1. 기본 Primitive와 커널 ROP

목표 : 기초를 검증하고, 취약점에서 최종 권한 상승까지의 흐름을 독립적으로 설명하기

|순서|문제|핵심 학습|
|---|---|---|
|1|welkerme(2022)|Kernel function pointer, ret2usr|
|2|driver4b(2023)|Usercopy, AAR/AAW|
|3|The jumps(2025)|Stack BOF, Kernel ROP|
|4|Baby Kernel(2025)|UAF, tty_struct|
|5|Flipper Hero(2024)|Arbitrary bit flip|

통과 기준 : 커널 베이스 주소, AAR, AAW primitive, 최종 익스플로잇 기법이 각각 왜 필요한지 설명할 수 있어야함.

## STAGE 2. SLUB과 Heap Exploitation

목표 : 단순히 UAF를 발생시키는 것이 아니라, 해제된 메모리에 원하는 객체를 재할당하는 원리를 이해하기

|순서|문제|핵심 학습|
|---|---|---|
|1|easy_kernel(2025)|Dangling pointer, seq_operations|
|2|xcache(2025)|Dedicated kmem_cache, freelist|
|3|free2free(2024)|Double free, heap overlap|
|4|Kuwu(2024)|msg_msg,pipe_buffer|
|5|pew(2025)|UAF, Drity Pipe|
|5|d3kheap2(2025)|Refcount, cross-cache|

통과 기준 : SLUB의 객체 재사용과 slab 페이지 재사용의 차이를 설명하고, heap reclaim 실패 원인을 디버깅할 수 있어야한다.

## STAGE 3. Race Condition과 객체 생명주기

목표 : 할당과 해제뿐 아니라, refcount, locking, mmap, workqueue의 시간적 관계 추적하기

|순서|문제|핵심 학습|
|---|---|---|
|1|hashbrown(2021)|Resize race, userfaultfd|
|2|kno_puts_revenge(2024)|Race UAF, freelist poisoning|
|3|DirtyFetch(2024)|Double-fetch, TOCTOU|
|4|atoms(2020)|vm_open, mmap refcount|
|5|umemo/kmemo(2023)|mmap_ownership, UAF|
|6|n1sub(2023)|UAF, pipe_buffer flags|

통과 기준 : 객체가 언제 살아있고, 언제 더 접근할 수 없어야 하는지 판단할 수 있어야함

## STAGE 4. 고급 커널 메모리 공격

목표 : 단순한 함수 포인터 덮어쓰기 이외의 복잡한 객체, 페이지 기반 primitive 이해하기

|순서|문제|핵심 학습|
|---|---|---|
|1|Sycrop(2023)|Stack pivot, ret2hbp|
|2|d3kcache(2023)|Off-by-one, pipe_buffer|
|3|kcipher(2023)|Uninitialized memory, fake object|
|4|heap_master(2024)|Cross-cache, PTE, DirtyPage|
|5|kpid(2024)|struct pid refcount, page table|
|6|keasy(2023)|struct file UAF, PTE reclaim|

## STAGE 5. 실제 커널 코드와 유사한 문제

목표 : 단순한 커스텀 드라이버 취약점을 넘어 실제 커널 서브시스템의 복잡한 로직 분석하기

|순서|문제|핵심 학습|
|---|---|---|
|1|N1khash(2025)|Delayed work UAF|
|2|File No!(2025)|seq_file, private_data|
|3|easy netlink(2023)|Netlink, heap overflow, race|
|4|Johnny Sins(2025)|Pipe page UAF|
|5|Matrix(2025)|eBPF verifier, range analysis|