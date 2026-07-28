# kernelCTF 조사 우선순위

기준일: 2026-07-28

| 순위 | 서브시스템 | syzbot 고유 버그 | Linux CNA CVE | 공개 kernelCTF |
|---:|---|---:|---:|---:|
| 1 | Networking (nftables 제외) | 1,852 | 1,693 | 57 |
| 2 | VFS / filesystems | 725 | 1,048 | 1 |
| 3 | BPF | 350 | 164 | 7 |
| 4 | Crypto / AF_ALG | 120 | 116 | 2 |
| 5 | Memory management | 533 | 59 | 0 |

## 집계 기준

- syzbot: upstream 서브시스템 페이지의 `fixed + open` 고유 버그. 자식 태그를 포함하는 상위 태그 기준.
- CVE: CVE List V5에서 `assignerShortName=Linux`인 2024-01-01~2026-07-28 레코드. CNA 제목의 서브시스템 prefix를 계층별로 합산.
- kernelCTF: Google `security-research/pocs/linux/kernelctf`의 공개 디렉터리를 CVE로 중복 제거한 뒤, 취약점의 **root-cause 서브시스템**으로 분류. LTS/COS/mitigation 변형은 1건으로 계산.
- 우선순위: 세 기록의 규모와 최신 LTS에서 비권한 사용자 도달 가능성을 함께 평가. 현재 비활성화된 nftables/io_uring 및 user namespace가 필요한 경로는 제외·감점.
- Networking의 통계에는 과거 netfilter 기록이 포함되지만, 조사 범위에서는 nftables를 제외한다.
- BPF는 `bpf()` eBPF 경로가 제한될 가능성이 높다. 비권한 classic BPF/socket-filter 경로를 우선한다.
- 파일시스템은 mount 권한이 필요한 디스크 이미지 파서보다 일반 VFS 및 이미 마운트된 pseudo/network filesystem 경로를 우선한다.

## 제외한 강한 과거 후보

| 후보 | 제외 이유 |
|---|---|
| nftables/netfilter | 최신 LTS target에서 nftables 비활성화 |
| io_uring | 최신 LTS target에서 비활성화 |
| mount 전용 filesystem parser | user namespace 비활성화로 비권한 mount 경로가 크게 축소 |
| USB device drivers | target에서 공격자가 제어하는 USB 장치 입력을 공급하기 어려움 |

## 출처

- syzbot: <https://syzkaller.appspot.com/upstream>
- CVE List V5: <https://github.com/CVEProject/cvelistV5>
- kernelCTF 공개 제출: <https://github.com/google/security-research/tree/master/pocs/linux/kernelctf>
- 현행 kernelCTF 규칙: <https://google.github.io/security-research/kernelctf/rules.html>

