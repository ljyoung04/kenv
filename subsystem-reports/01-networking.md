# Networking

## 선정 근거

- syzbot 1,852건, Linux CNA CVE 1,693건, 공개 kernelCTF 57건으로 세 지표 모두 최상위.
- 소켓 수명주기, `sk_buff`, 비동기 work/RCU, 프로토콜 상태 머신이 겹쳐 UAF·race·refcount 오류가 반복된다.
- 최신 target에서는 nftables와 user namespace 의존 netlink 설정을 제외한다. 비권한 TCP/UDP/AF_UNIX 및 허용된 socket option을 우선한다.

## 주요 객체

| 객체 | 역할 |
|---|---|
| `struct socket` | VFS file과 프로토콜 socket 연결 |
| `struct sock` | 공통 socket 상태, queue, callback, refcount |
| `struct sk_buff` | 송수신 packet buffer와 fragment metadata |
| `struct proto` / `struct proto_ops` | 프로토콜별 생성·송수신·해제 연산 |
| `struct net` | network namespace 상태; 최신 target에서는 생성 권한 제약 주의 |
| `struct net_device` | network interface와 packet RX/TX 경로 |
| `struct unix_sock` | AF_UNIX peer, inflight FD, receive queue |

## 엔트리 포인트

- `socket()`, `socketpair()`
- `bind()`, `connect()`, `listen()`, `accept4()`
- `sendmsg()`, `recvmsg()`, `sendmmsg()`, `recvmmsg()`
- `setsockopt()`, `getsockopt()`
- `shutdown()`, `close()`
- `ioctl()` on socket FD
- 제한 확인 후 rtnetlink/generic-netlink messages

## 우선 조사 경계

- AF_UNIX의 FD passing, OOB, garbage collection
- TCP/UDP의 close/error/zero-copy 비동기 경로
- TLS/XFRM은 비권한 설정 가능 여부를 먼저 확인
- 제외: nftables, `CAP_NET_ADMIN`/`CAP_NET_RAW`가 필요한 경로

## 출처

- <https://syzkaller.appspot.com/upstream/s/net>
- <https://github.com/CVEProject/cvelistV5>
- <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>

