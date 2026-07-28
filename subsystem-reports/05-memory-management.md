# Memory Management

## 선정 근거

- syzbot 533건, Linux CNA CVE 59건.
- 공개 kernelCTF root-cause는 0건이지만, 거의 모든 exploit primitive와 맞닿고 일반 메모리 syscall은 비권한 도달 가능하다.
- VMA split/merge, page pinning, reclaim, page fault의 교차 상태가 넓어 신규 bug 발굴 여지가 크다.

## 주요 객체

| 객체 | 역할 |
|---|---|
| `struct mm_struct` | 프로세스 address space |
| `struct vm_area_struct` | 연속 virtual memory range |
| `struct folio` / `struct page` | physical/page-cache memory 단위 |
| `struct anon_vma` | anonymous mapping reverse map |
| `struct address_space` | file-backed page cache |
| `struct mem_cgroup` | memory accounting·reclaim |
| `struct mmu_notifier` | secondary MMU invalidation |

## 엔트리 포인트

- `mmap()`, `munmap()`, `mprotect()`, `mremap()`
- `brk()`, `madvise()`, `mincore()`
- `mlock()`, `mlock2()`
- `userfaultfd()` — sysctl/권한 확인
- `process_madvise()`, `process_vm_readv()`, `process_vm_writev()`
- page fault through ordinary loads/stores
- file-backed mapping, `truncate()`, `fallocate()` 조합

## 우선 조사 경계

- VMA split/merge와 maple tree update
- GUP/page pin과 unmap/truncate race
- anonymous/file-backed page fault와 reclaim
- `mremap()`/`mprotect()` 경계 계산
- userfaultfd는 최신 target 허용 여부 확인 후 진행

## 출처

- <https://syzkaller.appspot.com/upstream/s/mm>
- <https://github.com/CVEProject/cvelistV5>
- <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>

