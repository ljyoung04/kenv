---
name: human-report
description: 커널 취약점 연구의 근본 원인, 재현기, 악용 영향, 패치, 심각도와 한계를 원본 증거에 대조하고 사람이 독립 검토할 수 있는 묶음과 보고서를 만든다. 최종 기술 검토와 KernelCTF 패키지 준비에 사용하며 원격 제출·외부 공개는 수행하지 않는다.
---

# Human Review Bundle

파이프라인 결과를 사람이 원본부터 독립적으로 재구성하고 판단할 수 있게 정리한다. 이전 단계의
결론을 매끄러운 보고서로 바꾸는 것이 아니라, 주장마다 근거를 대조해 불일치·누락·미검증 사항을
드러내는 마지막 품질 게이트다.

## 범위와 역할

- 루트 `AGENTS.md`, `scope.md`, `FINDINGS.md`와 해당 후보의 발견·검증·악용·패치 산출물을
  모두 읽는다. 적용되지 않거나 승인되지 않은 단계는 없다고 가정하지 말고 `not performed`로 쓴다.
- 검토 자료 준비와 기술 교차 검토는 `kernel_astra`/`gpt-6-astra`에 배정하고 실제 역할·모델을
  기록한다. 가능하면 핵심 결과를 만든 작업자와 다른 작업자가 검토한다.
- 산출물은 `agent/<research-name>/human-report/<vuln-name>/`에 만든다. 다른 작업의 보고서나
  원본 로그를 수정하지 않으며, 큰 원본은 복사보다 안정적인 상대 경로와 해시로 연결할 수 있다.
- 보고서 작성은 외부 보고·PR·업로드·플래그 제출·공개 승인이 아니다. 그런 행위는 사용자가
  목적지를 특정해 지시할 때만 별도로 수행한다.

## 입력 완전성 검사

Candidate-ID와 Target-ID가 모든 단계에서 같은지 확인하고 다음 연결을 검토한다.

```text
공격자 진입점
  -> 위반 불변식과 첫 잘못된 연산
  -> 최소 재현기의 런타임 관측
  -> 확인된 원시 효과
  -> 목표 영향과 사용한 정확한 취약점
  -> 패치가 회복한 불변식과 회귀 결과
```

각 화살표에 소스 위치, 설정, 원본 로그 또는 대조 실험이 없으면 보고서에 공백을 숨기지 않는다.
특히 다음을 독립 확인한다.

- 파일·심볼·행 번호·커밋·config·바이너리 해시가 실제 파일과 일치하는가?
- 재현 성공과 exploit 성공이 같은 근본 원인을 사용하며 다른 zero-day나 인프라 결함이 아닌가?
- 비특권·완화 활성·대상 일치 주장이 실제 실행 환경과 맞는가?
- 성공률의 분모, 시간 제한, 실패 유형과 깨끗한 VM 조건이 보존되었는가?
- 패치가 재현기만 막는 것이 아니라 근본 원인과 변종을 다루고 새 회귀를 만들지 않는가?
- 심각도는 입증된 영향과 도달 조건을 넘어서지 않는가?

불일치는 원본을 임의로 고쳐 합의시키지 말고 `review-findings.md`에 영향과 필요한 재작업 단계를
기록한다. 필수 인과가 깨지면 `READY`로 판정하지 않는다.

## 보고서 구성

다음 구조를 기본으로 하되 대상 프로그램이 요구하는 이름이 다르면 공식 형식을 따른다.

```
review-findings.md
MANIFEST.sha256
docs/
  vulnerability.md
  reproduction.md
  exploit.md
  patch.md
  limitations.md
evidence/
  index.md
  <필요한 원본 또는 상대 경로 목록>
repro/
  <최소 재현기와 빌드/실행 파일>
exploit/
  <exact-target>/
    exploit.c
    exploit
    Makefile
patch/
  fix.patch
  commit-message.txt
```

`vulnerability.md`에는 요약, 영향받는 정확한 리비전·설정, 위협 모델, 진입 경로, 근본 원인,
위반 불변식, 최초 잘못된 연산, 런타임 증거와 영향 판정을 쓴다. `reproduction.md`에는 준비와
공격자 동작을 분리한 명령, 기대 출력, 실패 진단, 성공/총 시도를 쓴다. `exploit.md`에는 목표,
프리미티브 체인, 대상 완화, 성공 증거, 신뢰성과 독립 인과 검토를 쓰되 미수행이면 그 사실을
명시한다. `patch.md`에는 수정 설계, base, 적용·빌드·회귀·변종 결과와 남은 위험을 쓴다.

보고서의 모든 중요한 주장은 `evidence/index.md`에서 원본 파일, 해시와 해당 위치로 추적할 수
있어야 한다. 재현에 불필요한 커널 이미지, vmlinux, 인증서, 토큰, 플래그, 개인 정보와 비밀은
묶음에 복사하지 않는다.

## KernelCTF 패키지 모드

KernelCTF용 검토가 요청되었으면 최종 정리 시점의
[공식 규칙](https://github.com/google/security-research/blob/master/kernelctf/rules.md), 제출 구조와
[metadata schema](https://google.github.io/security-research/kernelctf/metadata.schema.v3.json)를
다시 확인한다. 저장된 대상 이름과 예전 schema를 권위 있는 현재 규칙처럼 사용하지 않는다.
현재 요구 형식이 맞는 경우 일반 묶음 안에 다음을 추가한다.

```text
kernelctf/
  docs/
    vulnerability.md
    exploit.md
  exploit/
    <exact-target>/
      exploit
      exploit.c
      Makefile
  metadata.json
  original.tar.gz
  package-review.md
```

`original.tar.gz`는 공식 평가에 사용한 정확한 아카이브가 이미 존재할 때 그 원본과 해시를
보존한다. 새로 포장한 파일을 원래 제출물이라고 부르지 않는다. prebuilt `exploit`가 소스와
일치하고 외부 의존성 없이 현재 계약의 인자와 제한을 지키는지 확인한다.

`metadata.json`은 schema와 [로컬 예시](references/example.json)를 구조 참고용으로만 사용하고,
예시의 ID·CVE·커밋·버전을 복사하지 않는다. `submission_ids`, CVE, patch commit, 공식 안정성처럼
사용자 또는 공개된 최종 상태 없이는 알 수 없는 값은 만들어내지 않는다. 현재 schema가 빈 값을
허용하지 않으면 거짓 값으로 유효성 검사를 통과시키지 말고 `metadata.draft.json`에 빈 값으로
남긴 뒤 `package-review.md`에 `NEEDS_USER_DATA`와 필요한 필드를 열거한다. 모든 값이 확보된
`metadata.json`만 현재 schema로 검증해 제출 준비 완료로 표시한다.

공식 규칙의 0-day/공개·패치 시점, 중복, 활성 대상과 LTS trigger, 안정성·시간, 제출 기한은
각각 `PASS`, `FAIL`, `UNKNOWN`과 조회 시각·근거 URL로 기록한다. 공식 서비스 실행이나 양식·PR
제출은 패키지 작성에 포함되지 않는다.

## 최종 판정

| 상태 | 기준 |
|---|---|
| `READY_FOR_HUMAN_REVIEW` | 증거 연결과 필수 문서가 완전하며 사람이 명령대로 독립 검토할 수 있다. |
| `READY_FOR_AUTHORIZED_SUBMISSION` | 사람 검토 준비에 더해 현재 프로그램 형식·적격성·metadata가 확인됐다. 제출 자체는 하지 않는다. |
| `NEEDS_REWORK` | 인과, 재현, 영향, 패치 또는 문서의 필수 불일치가 있다. |
| `NEEDS_USER_DATA` | submission ID·CVE 등 에이전트가 만들 수 없는 필수 값이 없다. |
| `INCOMPLETE_EVIDENCE` | 필수 원본이나 해시가 없어 주장을 독립 확인할 수 없다. |

`review-findings.md` 첫 부분에 판정, 검토한 리비전·대상, 확인된 역할·모델, 주요 확인 사실,
차단 이슈와 정확한 다음 작업을 둔다. 마지막으로 `MANIFEST.sha256`을 검증하고, 링크·명령을
깨끗한 작업 디렉터리에서 읽기 전용으로 따라가 누락된 암묵적 상태가 없는지 확인한다.

## 설계 근거

OpenAI의 [루트 권한 탈취 경로 1,000개 줄이기](https://openai.com/ko-KR/index/a-thousand-fewer-paths-to-root/)
에서 마지막 사람이 근본 원인, 최소 PoC, 패치, 완전한 exploit과 제안 심각도를 함께 검토하는
구조 및 성공 경로를 독립 검증해야 한다는 교훈을 반영했다. 이 스킬의 준비 판정은 사람의 최종
판단이나 외부 프로그램의 적격성 결정을 대체하지 않는다.
