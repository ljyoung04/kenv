# Crypto / AF_ALG

## 선정 근거

- syzbot 120건, Linux CNA CVE 116건, 공개 kernelCTF 2건.
- `AF_ALG`는 일반 socket API로 crypto transform, scatterlist, async completion을 노출하며 user namespace나 nftables/io_uring에 의존하지 않는다.
- send/splice/recv와 비동기 crypto completion 사이의 ownership 오류를 집중 탐색할 수 있다.

## 주요 객체

| 객체 | 역할 |
|---|---|
| `struct crypto_tfm` | crypto transform 공통 객체 |
| `struct crypto_alg` | algorithm 등록 정보와 callback |
| `struct alg_sock` | AF_ALG socket 상태 |
| `struct af_alg_ctx` | 요청별 buffer와 completion 상태 |
| `struct scatterlist` | 비연속 입력·출력 buffer 기술 |
| `struct skcipher_request` | symmetric cipher 비동기 요청 |
| `struct aead_request` | AEAD 비동기 요청 |

## 엔트리 포인트

- `socket(AF_ALG, SOCK_SEQPACKET, 0)`
- `bind()` with `sockaddr_alg`
- `accept()`
- `setsockopt(ALG_SET_KEY/ALG_SET_IV/ALG_SET_OP/ALG_SET_AEAD_AUTHSIZE)`
- `sendmsg()`, `recvmsg()`
- `splice()`, `vmsplice()`
- `close()` 중 outstanding request teardown

## 우선 조사 경계

- zero-length·partial I/O와 short buffer
- scatterlist 길이/offset 계산
- async completion과 socket close/cancel race
- in-place encrypt/decrypt와 page pin ownership
- algorithm fallback·template 조합

## 출처

- <https://syzkaller.appspot.com/upstream/s/crypto>
- <https://github.com/CVEProject/cvelistV5>
- <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>

