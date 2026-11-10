# Kernel Exploit 학습 로드맵

**5단계 × 5문제, 총 25문제.** 난이도뿐 아니라 새로 배우는 기법, 선행 지식, 앞 문제와의 연결성을 기준으로 선정했다. C 포인터·구조체, 기본적인 x86-64 어셈블리와 사용자 공간의 스택 오버플로를 알고 있다는 전제다.

문제 이름은 저장소의 문제 폴더로, 배포 링크는 **기존 원본 파일**로 연결된다. 압축파일을 새로 만들거나 변환하지 않았다. `tar.gz`·`tgz`는 gzip으로 압축한 tar이며, ZIP·XZ·일반 tar·개별 파일 형태도 구분해 표시했다.

각 단계의 체크리스트에서 푼 문제는 `- [ ]`를 `- [x]`로 바꾸어 표시한다.

## 선정 기준과 진행 방법

- **취약점 → 확보한 능력 → 최종 목표**를 연결해서 학습한다. 같은 `modprobe_path` 덮어쓰기로 끝나더라도, 직접 제공된 임의 쓰기와 UAF·freelist 조작으로 만든 임의 쓰기는 별개의 학습 경험으로 본다.
- 직접적인 메모리 접근에서 시작해 스택 제어, 힙 객체 재사용, 경쟁 상태, 제한적인 메모리 손상과 특수 서브시스템으로 확장한다.
- 난이도는 루트 [README.md](./README.md)의 분류를 사용한다. 단계는 학습 주제의 순서이므로, 다음 단계의 첫 문제가 이전 단계의 마지막 문제보다 쉬울 수 있다.
- 로컬에 실제 배포 내용이 있는 문제를 우선했다. Git LFS 포인터만 있는 `below`, `kbuf`, `throughthewall` 등은 본 과정에서 제외했다. 파일 존재와 압축 내부 구성은 확인했지만, VM 부팅이나 풀이 성공을 검증한 목록은 아니다.
- 먼저 배포본을 분석하고, 막히면 문제 폴더의 `exploit/`, `writeup/`, README의 해설을 참고한다. 배포본 자체에 풀이가 포함된 `welkerme`, `window-of-opportunity`는 해당 파일을 나중에 보는 편이 좋다.

| 단계 | 중심 질문 | 새로 익힐 내용 |
|---|---|---|
| 1. 기본 권한과 메모리 접근 | 커널에서 무엇을 읽거나 바꿀 수 있는가? | ioctl, ret2usr, cred, AAR/AAW, 주소 누출, OOB |
| 2. 스택과 실행 흐름 | 보호기법을 고려해 실행 흐름을 어떻게 제어하는가? | task_struct, 스택 누출, canary, KASLR, kernel ROP, KPTI |
| 3. 힙과 객체 재사용 | 해제되거나 인접한 객체를 어떻게 이용하는가? | UAF, heap spray, tty_struct, seq_operations, pipe_buffer |
| 4. 경쟁 상태 | 잘못된 상태가 생기는 타이밍을 어떻게 만드는가? | TOCTOU, double fetch, userfaultfd, race UAF, 잠금 분석 |
| 5. 심화와 기법 확장 | 약한 손상이나 다른 서브시스템에서 어떻게 출발하는가? | freelist poisoning, msg_msg, FG-KASLR, cross-cache, eBPF verifier |

## 1단계 — 커널 권한과 기본 읽기·쓰기

목표는 드라이버 인터페이스를 이해하고, 제어 가능한 입력을 정확한 읽기·쓰기 능력으로 설명하는 것이다. 복잡한 힙 배치나 경쟁 상태 없이 권한 상승의 기본 구성 요소부터 익힌다.

- [ ] 1-1 welkerme
- [ ] 1-2 driver4b
- [ ] 1-3 Baby Kernel 2
- [ ] 1-4 echo
- [ ] 1-5 KList

| 순서 | 문제 · 원본 난이도 | 배울 기법과 선정 이유 | 원본 배포 |
|---|---|---|---|
| 1-1 | [welkerme — CakeCTF 2022](./2022/CakeCTF_2022/Pwn_welkerme) · Very-Easy | 사용자 함수 포인터를 커널에서 호출하는 인터페이스. SMEP가 꺼진 환경에서 ret2usr와 `commit_creds` / `prepare_kernel_cred`의 역할을 가장 단순한 형태로 익힌다. | [tar.gz](./2022/CakeCTF_2022/Pwn_welkerme/distribution/welkerme_afcc40e7baa18649730945cde6475354.tar.gz) |
| 1-2 | [driver4b — SECCON Beginners CTF 2023](./2023/SECCON_Beginners_CTF_2023/Pwn_driver4b) · Easy | usercopy 검증 누락으로 AAR/AAW를 얻는다. 소스와 debug/release 환경이 있어 ioctl 사용법, 사용자·커널 포인터의 경계, 데이터 덮어쓰기를 연습하기 좋다. | [개별 파일](./2023/SECCON_Beginners_CTF_2023/Pwn_driver4b/distribution) |
| 1-3 | [Baby Kernel 2 — Hack.lu CTF 2019](./2019/Hack.lu_CTF_2019/Pwn_Baby_Kernel_2) · Easy | 임의 읽기·쓰기를 `cred` 변조로 연결한다. 앞 문제의 전역 변수 덮어쓰기와 비교하며, 실행 흐름을 바꾸지 않고 권한을 바꾸는 방법을 배운다. | [zip](./2019/Hack.lu_CTF_2019/Pwn_Baby_Kernel_2/distribution/baby_kernel_2_7787916f9b06d129da1aae2dc2b5f42a.zip) |
| 1-4 | [echo — 3kCTF 2021](./2021/3kCTF-2021/Pwn_echo) · Easy | 위험한 syscall이 제공하는 8바이트 읽기·쓰기와 physmap 누출을 다룬다. 주소가 고정된 상황에서 한 걸음 나아가 주소 복원과 KASLR 우회를 연결한다. | [tgz](./2021/3kCTF-2021/Pwn_echo/distribution/echo-447e7d55a7bc1f96518a18b7d645320b.tgz) |
| 1-5 | [KList — ASIS CTF Finals 2025](./2025/ASIS_CTF_Finals_2025/Pwn_KList) · Easy | 경계 검사 누락으로 연결 리스트의 메타데이터를 손상시킨다. 이미 주어진 AAR/AAW를 사용하는 단계에서 벗어나, OOB와 포인터 변조로 접근 범위를 넓히는 연습이다. | [txz](./2025/ASIS_CTF_Finals_2025/Pwn_KList/distribution/KList_72e19ffc15bfaa254550ea7091a9eee7e3c95f86.txz) |

**완료 기준:** 각 문제에서 제어 가능한 주소·크기·값을 설명하고, 커널 코드 실행과 데이터만 바꾸는 권한 상승의 차이를 설명할 수 있다.

## 2단계 — 스택, 주소 누출, 보호기법

선행 지식은 1단계의 AAR/AAW와 커널 주소 개념이다. 스택의 메모리 접근부터 시작해 ROP와 사용자 공간 복귀를 익힌 뒤, 누출 경로가 달라져도 같은 원리를 적용한다.

- [ ] 2-1 Teen Kernel
- [ ] 2-2 babyk
- [ ] 2-3 Easy kernel is still kernel right?
- [ ] 2-4 xen
- [ ] 2-5 window-of-opportunity

| 순서 | 문제 · 원본 난이도 | 배울 기법과 선정 이유 | 원본 배포 |
|---|---|---|---|
| 2-1 | [Teen Kernel — Hack.lu CTF 2019](./2019/Hack.lu_CTF_2019/Pwn_Teen_Kernel) · Easy-Medium | 검증하지 않은 커널 스택 오프셋을 이용한 접근과 `task_struct` / `cred` 탐색. 1단계의 메모리 읽기를 커널 내부 구조를 찾아가는 과정으로 확장한다. | [zip](./2019/Hack.lu_CTF_2019/Pwn_Teen_Kernel/distribution/teen_kernel_0f7e4ddbc7201eee2a447cc5e2b6a320.zip) |
| 2-2 | [babyk — m0leCon CTF 2020 Teaser](./2020/m0leCon_CTF_2020_Teaser/Pwn_babyk) · Easy | 단순 스택 BOF와 저장된 반환 주소 제어. KASLR이 꺼진 환경에서 커널 실행 흐름 제어와 사용자 공간 복귀를 먼저 익힌다. ret2usr와 저장소의 ROP 풀이를 비교하기 좋다. | [zip](./2020/m0leCon_CTF_2020_Teaser/Pwn_babyk/distribution/babyk.zip) |
| 2-3 | [Easy kernel is still kernel right? — K3RN3LCTF](./2021/K3RN3LCTF/Pwn_Easy_kernel_is_still_kernel_right) · Easy | 스택 누출로 canary와 커널 주소를 얻고 BOF에 연결한다. SMEP/SMAP, KASLR, canary, KPTI의 역할을 구분하면서 kernel ROP의 기본 흐름을 완성한다. | [tar.gz](./2021/K3RN3LCTF/Pwn_Easy_kernel_is_still_kernel_right/distribution/easy_kernel.tar.gz) |
| 2-4 | [xen — L3akCTF 2024](./2024/L3akCTF_2024/Pwn_xen) · Easy | 스택 canary 누출과 `/sys/kernel/notes`를 통한 주소 누출을 조합한다. 서로 다른 누출을 모아 ROP를 구성하고 `commit_creds(&init_cred)` 및 KPTI 복귀를 연습한다. | [zip](./2024/L3akCTF_2024/Pwn_xen/distribution/xen_players.zip) |
| 2-5 | [window-of-opportunity — ImaginaryCTF 2023](./2023/ImaginaryCTF_2023/Pwn_window-of-opportunity) · Medium | unsafe usercopy에서 얻는 읽기 능력과 스택 BOF를 결합한다. 모듈 리버싱을 통해 입력 구조와 누출·덮어쓰기 경로를 직접 복원하는 종합 문제다. | [zip](./2023/ImaginaryCTF_2023/Pwn_window-of-opportunity/distribution/opportunity_dist.zip) |

**완료 기준:** 누출이 필요한 이유, canary를 보존해야 하는 이유, 커널 권한 획득 뒤 사용자 공간으로 정상 복귀하는 과정을 설명할 수 있다. 보호기법은 문제별 실행 스크립트와 커널 설정을 보고 확인한다.

## 3단계 — 힙, UAF, 커널 객체 재사용

선행 지식은 메모리 누출과 함수 포인터·ROP의 역할이다. 서로 다른 커널 객체를 이용해 주소 누출, 읽기·쓰기, 실행 흐름 제어를 만드는 방법을 비교한다.

- [ ] 3-1 clipboard.ko
- [ ] 3-2 switchboard
- [ ] 3-3 meowmow
- [ ] 3-4 forest
- [ ] 3-5 Full Chain - Wall Rose

| 순서 | 문제 · 원본 난이도 | 배울 기법과 선정 이유 | 원본 배포 |
|---|---|---|---|
| 3-1 | [clipboard.ko — TSJ CTF 2022](./2022/TSJ_CTF_2022/Pwn_clipboard.ko) · Easy | kmalloc-1024 UAF와 `tty_struct` 겹침. 해제된 객체를 다른 종류의 객체로 재할당하는 heap spray와 함수 포인터 변조를 처음 연습한다. | [tar.gz](./2022/TSJ_CTF_2022/Pwn_clipboard.ko/distribution/clipboard.tar.gz) |
| 3-2 | [switchboard — PatriotCTF 2025](./2025/PatriotCTF_2025/Pwn_switchboard) · Easy-Medium | kmalloc-32의 작은 객체를 재사용한다. 큰 `tty_struct`를 쓰던 접근에서 벗어나, 대상 크기와 레이아웃에 맞는 재할당 전략을 생각하게 한다. | [tar](./2025/PatriotCTF_2025/Pwn_switchboard/distribution/dist.tar) |
| 3-3 | [meowmow — zer0pts CTF 2020](./2020/zer0pts_CTF_2020/Pwn_meowmow) · Easy-Medium | 전방 OOB 읽기·쓰기, `tty_struct` 누출, 가짜 `tty_operations`. 같은 tty 계열 객체라도 UAF가 아닌 인접 메모리 손상에서 출발하는 방법을 배운다. | [tar.gz](./2020/zer0pts_CTF_2020/Pwn_meowmow/distribution/meowmow_169ccab501964888b43108512ae39eeb.tar.gz) |
| 3-4 | [forest — GACTF 2020](./2020/GACTF2020/Pwn_forest) · Easy-Medium | UAF/double free와 `seq_operations` 재사용을 kernel ROP로 연결한다. 힙 손상이 2단계에서 배운 실행 흐름 제어의 출발점이 될 수 있음을 익힌다. | [zip](./2020/GACTF2020/Pwn_forest/distribution/forest_attachment.zip) |
| 3-5 | [Full Chain - Wall Rose — HITCON CTF 2023 Quals](./2023/HITCON_CTF_2023_Quals/Pwn_Full_Chain-Wall_Rose) · Easy-Medium | 전역 포인터 double free, `pipe_buffer` 겹침, Dirty Pipe 방식의 페이지 캐시 변조. 커널 오프셋에 의존하지 않는 풀이를 목표로 하며, ROP 외의 공격 경로를 배운다. | [tgz](./2023/HITCON_CTF_2023_Quals/Pwn_Full_Chain-Wall_Rose/distribution/wall-rose-a10160050459354487c14f76f6bbd783d8d02c91.tgz) |

**완료 기준:** 객체 크기·할당 캐시·수명을 표로 정리하고, 왜 해당 객체가 원하는 위치를 차지할 수 있는지 설명할 수 있다. `tty_struct`, `seq_operations`, `pipe_buffer`에서 각각 어떤 필드가 유용한지 비교한다.

## 4단계 — 경쟁 상태와 실행 시점 제어

선행 지식은 2단계의 스택 공격과 3단계의 UAF다. 경쟁에서 이긴 뒤 무엇을 얻는지가 서로 다른 문제를 골랐다. 반복 성공률과 실패 원인까지 기록하며 푼다.

- [ ] 4-1 kpets
- [ ] 4-2 SYS_jail
- [ ] 4-3 DirtyFetch
- [ ] 4-4 lkgit
- [ ] 4-5 hashbrown

| 순서 | 문제 · 원본 난이도 | 배울 기법과 선정 이유 | 원본 배포 |
|---|---|---|---|
| 4-1 | [kpets — Facebook CTF 2019](./2019/Facebook_CTF_2019/Pwn_kpets) · Easy-Medium | TOCTOU로 1바이트 OOB 쓰기를 만들고 인접 객체의 필드에 영향을 준다. 검사 시점과 사용 시점의 차이를 작은 손상으로 관찰하기 좋다. | [tar.gz](./2019/Facebook_CTF_2019/Pwn_kpets/distribution/kpets.tar.gz) |
| 4-2 | [SYS_jail — KITCTFCTF 2022](./2022/KITCTFCTF_2022/Pwn_SYS_jail) · Easy-Medium | 사용자 포인터를 여러 번 읽는 double fetch. 사용자 메모리 값의 변경이 커널의 검사를 무효화하는 과정을 이해하고 `cred` 변조와 연결한다. | [tar.gz](./2022/KITCTFCTF_2022/Pwn_SYS_jail/distribution/sys_jail.tar.gz) |
| 4-3 | [DirtyFetch — PatriotCTF 2024](./2024/PatriotCTF_2024/Pwn_DirtyFetch) · Medium | 초기화되지 않은 스택 누출과 double-fetch 경쟁으로 스택 BOF를 만든다. 2단계에서 배운 ROP를, 경쟁 상태로 확보한 손상 능력 뒤에 연결한다. | [tar.gz](./2024/PatriotCTF_2024/Pwn_DirtyFetch/distribution/dirty_fetch.tar.gz) |
| 4-4 | [lkgit — TSG CTF 2021](./2021/TSG_CTF_2021/Pwn_lkgit) · Medium | 객체 교체 경쟁으로 생기는 UAF, `userfaultfd`, `seq_operations` 누출. 무작정 스레드를 반복 실행하는 방식에서 나아가 페이지 폴트를 이용해 실행 시점을 제어한다. | [tar.gz](./2021/TSG_CTF_2021/Pwn_lkgit/distribution/lkgit.tar.gz) |
| 4-5 | [hashbrown — DiceCTF 2021](./2021/DiceCTF_2021/Pwn_hashbrown) · Medium | resize와 일반 연산의 잠금 불일치, race UAF, `userfaultfd`와 객체 재사용을 종합한다. 저장소 해설의 `pipe_buffer`·페이지 캐시 경로는 비의도 풀이이므로, 의도 풀이와 구분해 비교한다. | [개별 파일](./2021/DiceCTF_2021/Pwn_hashbrown/distribution) |

**완료 기준:** 두 실행 흐름의 순서를 그려 취약한 구간과 동기화 지점을 표시할 수 있다. 단순 재시도와 `userfaultfd`를 이용한 제어의 차이를 설명하고, 여러 번 실행한 결과를 기록한다.

## 5단계 — 제한적인 손상, 방어기법, 다른 서브시스템

앞 단계의 능력을 조합하거나 적용 범위를 넓히는 단계다. 마지막 두 문제는 각각 cross-cache와 eBPF라는 추가 학습 주제가 있으므로, 익숙한 커널 pwn 템플릿을 그대로 적용하기보다 메모리 관리와 verifier의 모델부터 정리한다.

- [ ] 5-1 Shared House
- [ ] 5-2 Mini memo
- [ ] 5-3 kernel-rop
- [ ] 5-4 d3kheap2
- [ ] 5-5 d3bpf

| 순서 | 문제 · 원본 난이도 | 배울 기법과 선정 이유 | 원본 배포 |
|---|---|---|---|
| 5-1 | [Shared House — ASIS CTF Quals 2020](./2020/ASIS_CTF_Quals_2020/Pwn_Shared_House) · Easy-Medium | off-by-one NULL 쓰기를 SLUB freelist poisoning으로 확장한다. 원하는 값을 마음대로 쓸 수 없는 상황에서 할당 위치를 바꾸는 원리를 배운다. | [txz](./2020/ASIS_CTF_Quals_2020/Pwn_Shared_House/distribution/shared_distfiles_09110598594a19f1e3f0ebdd3917ed273953d16d.txz) |
| 5-2 | [Mini memo — ASIS CTF Quals 2021](./2021/ASIS_CTF_Quals_2021/Pwn_Mini_memo) · Medium | 3바이트 OOB에서 `msg_msg` 겹침, `pipe_buffer` 누출, freelist poisoning으로 이어진다. 약한 쓰기를 더 강한 읽기·쓰기 능력으로 단계적으로 확장하는 종합 문제다. | [txz](./2021/ASIS_CTF_Quals_2021/Pwn_Mini_memo/distribution/minimemo_de43a2690b3eba4b40f2404a1291f15305ddc94e.txz) |
| 5-3 | [kernel-rop — hxp CTF 2020](./2020/hxp_CTF_2020/Pwn_kernel-rop) · Medium-High | 스택 BOF에 FG-KASLR과 `ksymtab` 해석을 추가한다. 2단계의 ROP 지식을 바탕으로, 커널 베이스만 알아서는 함수 주소를 구하기 어려운 경우를 다룬다. | [tar.xz](./2020/hxp_CTF_2020/Pwn_kernel-rop/distribution/kernel-rop-bf9c106d45917343.tar.xz) |
| 5-4 | [d3kheap2 — D³CTF 2025](./2025/D%5E3CTF_2025/Pwn_d3kheap2) · Medium | 전용 `kmem_cache`의 refcount 오류/double free를 cross-cache 겹침으로 확장한다. `msg_msg`와 `pipe_buffer`를 사용하면서 같은 kmalloc 캐시 안에서만 객체를 재사용하던 가정을 넘어선다. | [zip](./2025/D%5E3CTF_2025/Pwn_d3kheap2/distribution/d3kheap2-4204275103428981b4c1eacde20e7b62665d7c87ad2d9a3f3ea9341ef9bdb01c.zip) |
| 5-5 | [d3bpf — D³CTF 2022](./2022/D%5E3CTF_2022/Pwn_d3bpf) · Medium-High | eBPF verifier의 shift 범위 추론과 실제 실행 값 사이의 불일치. eBPF 명령·레지스터·map·범위 추적을 먼저 익힌 뒤, 검증 오류를 OOB 및 AAR/AAW로 확장한다. | [zip](./2022/D%5E3CTF_2022/Pwn_d3bpf/distribution/d3bpf-fe89139cf452491fc88158f672848c50a372e2ce6811644b28035361ea4fbd01.zip) |

**완료 기준:** 각 풀이를 “취약점 → 첫 번째 능력 → 능력 확장 → 보호기법 처리 → 목표 달성”으로 정리할 수 있다. 커널 버전, allocator, 객체 크기, 설정이 달라질 때 풀이의 어느 가정이 깨지는지 설명한다.

## 기법별 복습 지도

| 복습할 내용 | 문제 연결 |
|---|---|
| 직접 주어진 메모리 접근 → 직접 만들어낸 접근 | driver4b → echo → KList → Mini memo |
| 데이터만 바꾸는 권한 상승 | Baby Kernel 2 → Teen Kernel → SYS_jail |
| 스택 손상 → 누출과 보호기법 → 주소 난수화 심화 | babyk → Easy kernel → xen → window-of-opportunity → kernel-rop |
| 힙 객체를 통한 함수 포인터 제어 | clipboard.ko → meowmow → forest |
| 작은 객체의 재사용과 수명 관리 | switchboard → lkgit |
| 제한된 쓰기 → allocator 조작 | Shared House → Mini memo |
| 페이지 캐시와 서로 다른 할당 캐시 | Wall Rose → hashbrown → d3kheap2 |
| 경쟁으로 만들어지는 손상 | kpets → SYS_jail → DirtyFetch → lkgit → hashbrown |
| 드라이버 취약점 밖으로 확장 | d3bpf |

## 배포본을 사용할 때 알아둘 점

이는 실행 환경을 새로 구성한 묶음이 아니라 **원본 배포본을 이용하는 학습 목록**이다.

- `driver4b`는 debug/release 환경을 모두 제공하며, `SYS_jail`은 `deploy/`에 실행용 이미지가 있다.
- `lkgit`과 `kpets`는 중첩된 압축파일이 있다. `lkgit` 내부 tar에는 `rootfs.cpio`의 중복 자기 참조 hardlink 항목도 있다.
- `babyk`, `DirtyFetch`, `hashbrown`, `Wall Rose`의 실행 스크립트에는 대회 서버 기준 절대 경로가 있다. 로컬에서 사용할 때 해당 경로를 확인해야 한다.
- `meowmow`와 `kpets`의 원본 실행 스크립트는 KVM을 사용한다. 가상화 지원 여부를 확인한다.
- `window-of-opportunity`는 실행 인자에 따라 `nokaslr`/`kaslr` 설정이 다르다. `kernel-rop`의 실행 스크립트가 요구하는 `flag.txt`는 원본 압축파일에 없어 로컬 연습용 파일이 필요하다.
- 문제 설명에 남은 대회 서버 주소 대신 제공된 커널·rootfs를 이용한 로컬 QEMU 환경에서 학습한다. 여기서 배우는 기법은 해당 문제의 커널 버전과 설정을 전제로 한다.

선정 근거는 저장소의 [문제 목록](./README.md), [기법 인덱스](./TECHNIQUES.md), 개별 문제 설명·로컬 해설·배포본이다. 외부 해설의 내용과 링크 유효성은 별도로 검증하지 않았다.


