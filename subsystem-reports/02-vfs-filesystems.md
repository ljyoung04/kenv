# VFS / Filesystems

## 선정 근거

- syzbot 725건, Linux CNA CVE 1,048건으로 결함 밀도가 높다.
- pathname lookup, inode/dentry 수명주기, page cache, writeback이 비동기로 교차한다.
- 공개 kernelCTF root-cause는 1건이지만 일반 파일 API는 user namespace 없이도 넓게 도달 가능하다.

## 주요 객체

| 객체 | 역할 |
|---|---|
| `struct file` | 열린 FD의 상태와 `file_operations` |
| `struct inode` | 파일 metadata와 filesystem별 inode |
| `struct dentry` | pathname component와 dcache 수명주기 |
| `struct super_block` | 마운트된 filesystem 인스턴스 |
| `struct path` | `vfsmount + dentry` 경로 |
| `struct address_space` | page cache와 writeback 연산 |
| `struct fs_context` | mount 구성 상태 |

## 엔트리 포인트

- `openat2()`, `close()`
- `read()`, `write()`, `preadv2()`, `pwritev2()`
- `renameat2()`, `linkat()`, `unlinkat()`, `mkdirat()`
- `statx()`, `getdents64()`
- `fcntl()`, `ioctl()`, `fallocate()`
- `splice()`, `sendfile()`, `copy_file_range()`
- `inotify_*()`, `fanotify_*()`(권한 확인)

## 우선 조사 경계

- dentry/inode reclaim과 lookup·rename 동시성
- file descriptor table과 close-on-exec/dup race
- pipe/splice와 page-cache ownership
- procfs, sysfs, tmpfs 등 target에 이미 마운트된 filesystem
- 제외: 새 mount에 `CAP_SYS_ADMIN` 또는 user namespace가 필요한 parser

## 출처

- <https://syzkaller.appspot.com/upstream/s/fs>
- <https://github.com/CVEProject/cvelistV5>
- <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>

