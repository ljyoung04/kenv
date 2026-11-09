---
name: kctf-official-helper
description: 사용자가 정확한 행위와 목적지를 승인한 KernelCTF 공식 서비스 정보 조회, 아티팩트 확보, LTS 트리거 및 hardened 익스플로잇 시험을 안전하게 수행하고 증거를 보존한다. 공개 규칙 조회만 하거나 승인되지 않은 원격 평가·제출에는 사용하지 않는다.
---

# KernelCTF Official Helper

KernelCTF 공식 원격 서비스와의 상호작용을 공개 정보 조회와 시도를
소모하는 실행으로 구분하고, 정확한 대상·페이로드·결과를 재구성할 수 있게
보존한다. 이 스킬은 원격 이용 승인을 제공하지 않는다.

## 시작 게이트

1. 루트 `AGENTS.md`와 적용 중인 단계 스킬을 먼저 읽는다.
2. 작업 시점의 [KernelCTF 공식 규칙](https://github.com/google/security-research/blob/master/kernelctf/rules.md)과
   [공식 서비스 안내](https://google.github.io/security-research/kernelctf/server/)를 확인하고
   조회 시각, URL, 활성 target/LTS, 실행 제한을 기록한다.
3. 원격 접속 전에 사용자가 승인한 `action`, 목적지, Candidate-ID, Target-ID,
   업로드할 정확한 파일과 최대 시도 횟수를 확인한다. `connect.sh`나 인증서가
   존재한다는 사실, 이전의 다른 action 승인, 로컬 테스트 승인으로 원격 승인을
   추정하지 않는다.

공개 웹에서 규칙·소스·릴리스 메타데이터·아티팩트를 읽는 작업은 루트
`AGENTS.md`의 읽기 전용 범위다. 그러나 공식 평가 서비스에 접속하는 `info`도
외부 서비스 이용이므로 명시적 승인 후에만 실행한다. 공개 정보로 대체할 수 있으면
원격 `info`보다 공개 정보를 우선한다.

## action 구분

| action | 용도 | 추가 주의 |
|---|---|---|
| `info` | 활성 target, config, 커널 릴리스와 공개 아티팩트 URL 확인 | 정보 조회 외의 메뉴로 진행하지 않는다. |
| `vuln-test` | 지정 LTS/LTS-KASAN에서 `--vuln-trigger` 경로 확인 | 커널 크래시는 재현 증거일 뿐 exploit 성공이 아니다. |
| `lpe-test` | hardened target에서 플래그 획득 경로 시험 | 정확한 시작 권한과 target의 완화를 기록한다. |
| `evaluate` | 공식 계약의 전체 평가 | 제한된 평가 횟수를 소모하므로 해당 action과 횟수를 명시한 승인이 필요하다. |
| `exit` | 상호작용 종료 | 예상하지 못한 프롬프트, target, 인증 요구, 업로드 범위가 나오면 종료한다. |

`lpe-test`, `vuln-test`, `evaluate`는 각각 별도의 원격 실행이다. 하나의 action에
대한 승인을 나머지 action으로 확장하지 않고, 제출 양식·플래그 제출·PR·외부
보고는 어떤 action 승인에도 포함되지 않는다.

## 실행과 증거 보존

- 현재 `/workspace/tools/connect.sh`와 CA 인증서 경로를 읽고, 기본 목적지가
  `kernelctf.vrp.ctfcompetition.com:1337`임을 확인한다. 다른 목적지는 사용자가
  명시한 경우에만 인수로 전달한다.
- 상호작용 접속은 PTY에서 `tools/connect.sh [host:port]`로 실행한다. 프롬프트를
  추정해 무인 입력을 보내지 말고, 현재 서버가 표시한 action과 target을 확인한다.
- 업로드 전에 페이로드의 경로, 크기, SHA-256, 빌드 명령, Candidate-ID/Target-ID를
  기록한다. 인증 토큰·세션 키·플래그는 명령행, 공유 로그, `FINDINGS.md`에
  노출하지 않는다.
- 각 시도의 시작/종료 시각, action, 서버가 보고한 정확한 target/release, 페이로드
  해시, 결과, 소요 시간, 남은 시도 예산을
  `agent/<research-name>/official/<run-id>/`에 보존한다. 민감한 원본은 제외한
  transcript와 해시를 남긴다.
- `info`가 제공한 공개 HTTPS 아티팩트는 target/release를 URL과 다시 대조하고
  다운로드한다. 커널 소스·`bzImage`·`vmlinux`·config는 루트 규칙에 따라
  `kernels/`에 덮어쓰지 않는 대상별 경로로 보존하고 SHA-256을 인계 기록에 남긴다.

승인된 횟수를 소모하거나, 정확한 결과를 얻거나, 대상/프롬프트/인증 요구가
예상과 다르거나, 인프라 오류로 유효한 실험을 계속할 수 없으면 종료한다. 신규
action, 추가 시도, 제출이 필요하면 현재 결과와 새 부수 효과를 보고하고 다시 승인받는다.

