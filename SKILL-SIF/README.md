# SKILL-SIF — 커널 취약점 스킬 자가 개선 공간

[arXiv:2610.25705v1](https://arxiv.org/html/2610.25705v1)의 SKILL-SIF(반복적 자가 개선
프레임워크)를 이 저장소에 맞게 옮기고 확장한 작업 공간이다. 공개된 실제 CVE로 케이스를
만들고, 서브 에이전트가 스킬로 root cause를 찾고 KASAN PoC를 만드는지 채점한다. 같은 조건에서
스킬 없이 푸는 대조군과 비교하고, 반복된 실패에서 교훈을 뽑아 스킬 사본을 고친 뒤 다시
채점한다.

운영 절차와 규칙은 `links/skills/skill-sif/SKILL.md`가 기준이다. 이 문서는 구조 안내다.

## 대상 스킬

| 스킬 | 과제 | 수정 가능 범위 |
|---|---|---|
| `vuln-discovery` | Part 1: 정적 root cause | `sif:protected` 블록을 뺀 전부 |
| `dynamic-validation` | Part 2: KASAN 재현기 | `sif:editable` 블록(§3 재현 루프, §4 인과 확인)만 |

## 루프

```text
오케스트레이터(세션)                          서브에이전트 (Opus 5.5, effort medium)
─────────────────────────────────           ─────────────────────────────────────
케이스 수집(인터넷 허용) → case add/verify/review
dispatch control   ──────────────────명령──▶ control × 케이스 × 3회 (스킬 없음, 자기 VM 사용)
score control      ◀─────────────────결과─── report.json, poc.c → PoC를 새 VM에서 재실행해 채점
gen init
dispatch detector  ──────────────────명령──▶ detector × 케이스 × 3회 (스킬 사본 사용, 자기 VM 사용)
score gen-NN       ◀─────────────────결과─── rc_rate, poc_rate, combined, 대조군 대비 효과
dispatch diagnoser ──────────────────명령──▶ diagnoser × 과반 실패 케이스
diagnose → lessons/gen-NN.md → gen new → 스킬 사본 수정 → gen lint → dispatch detector …
정지 규칙 → freeze → test 분할(대조군, gen-00, 동결 세대) → promote --auto (조건 충족 시만 반영)
```

| 논문 | 이 공간 |
|---|---|
| 수정 커밋의 첫 부모로 만든 수정 전 스냅샷 (git 이력 없음) | 오케스트레이터가 수집 → `case add`가 서브시스템과 include 헤더만 추출 |
| 패치에서 뽑은 정답 (책임 구문, 포함 함수) | `truth.json` (+ 공개 PoC의 KASAN 리포트에서 뽑은 `kasan.functions`) |
| CWE·함수·구문 3가지 검사 | `rc_rate` (케이스당 3회 실행 중 fully correct 비율) |
| (없음) | `poc_rate`: 최종 PoC를 새 격리 VM에서 재실행해 정답 위치의 KASAN 리포트가 나온 비율 |
| (없음) | 스킬을 쓰지 않는 대조군, 효과 = 실험군 − 대조군, 암기 의심 케이스 표시 |
| 실패 궤적 진단 → failure lessons | diagnoser → `lessons/gen-NN.md` (과반 실행에서 반복된 실패만) |
| 최대 10라운드, 2라운드 무개선 시 종료, 최고 세대 동결 | `config.json`의 `max_rounds`, `patience`, 예산 소진 |
| 독립 테스트 세트 | `cases/test/`: 동결 후 대조군, gen-00, 동결 세대만 실행 |

## 구조

```text
SKILL-SIF/
├── bin/sif              드라이버 (python3, 외부 의존성 없음)
├── agents/              역할 지침 (detector.md, control.md, diagnoser.md)
├── config.json          모델·effort, 실행 횟수, PoC 한도, 예산, 반영 조건
├── state.json           기준 해시, 열린 탐지 단계와 잠금, 실행 profile, 동결/반영 상태
├── links/               작업 공간 밖으로 나가는 통로 (심볼릭 링크)
│   ├── skills   → ../../.claude/skills   대상 스킬 (promote 때만 쓰기)
│   ├── tools    → ../../tools            vm.sh
│   ├── profiles → ../../profiles         실행별 VM profile `sif-*` (sif가 만들고 지움)
│   ├── kernels  → ../../kernels          케이스 커널 원본 (읽기)
│   ├── images   → ../../images           게스트 이미지 (읽기)
│   └── AGENTS.md
├── inbox/<folder>/      수집한 자료 (src/, sol.md, fix.patch, poc/, kasan.log, config)
├── cases/{refine,test}/<id>/   case.json, truth.json, src/, sol.md, fix.patch, poc/, kasan.log, verify/
├── vmimg/<img>/         케이스 KASAN 커널 (불투명 이름; bzImage, vmlinux)
├── generations/gen-NN/  GEN.json + skills/{vuln-discovery,dynamic-validation}/
├── runs/control/<split>/<id>/r<k>/   대조군 실행
├── runs/gen-NN/<split>/<id>/r<k>/    실험군 실행 (task.md, src/, skills/, out/, agent/, vmlogs/, score/)
├── scores/{control,gen-NN}.<split>.json
├── lessons/gen-NN.md
├── REPORT.md            세션 보고서
├── archive/             promote 직전 백업, 제외된 케이스
└── docs/failure-taxonomy.md
```

## 격리

- 탐지 단계가 열리면 `inbox/`, `cases/`, `generations/`, `lessons/`, `scores/`, `archive/`와
  라이브 스킬 디렉터리를 권한 000으로 잠근다. 대조군 단계에서는 실험군 실행 디렉터리도 잠근다.
  `sif score`가 잠금을 풀고 단계를 닫는다.
- 실행마다 무작위 이름의 VM profile을 하나씩 만든다. 이 profile은 `NET_ISOLATED=1`이라 게스트가
  네트워크에 나갈 수 없고, 커널 경로도 불투명하다. 채점할 때 VM 로그를 실행 디렉터리로 옮기고
  profile을 지운다.
- 권한 잠금은 샌드박스가 아니다. 그래서 `sif score`가 실행 기록에서 정답 경로, 다른 실행,
  (대조군의 경우) 스킬 파일, 다른 profile에 접근한 흔적을 찾는다. 흔적이 있으면 그 실행을
  실패로 처리하고 1회 재실행한다.
- 공식 KASAN 아티팩트는 `uname -r`과 부팅 배너에 커널 버전이 드러난다. 이런 케이스는
  `version_exposed`로 기록한다. 실험군과 대조군이 같은 조건이라 비교는 유효하다.

## 현재 상태

케이스가 아직 없다. `gen-00`은 이번 개편으로 바뀐 라이브 스킬 두 개를 복사한 기준선이다.
실제 탐지 실행은 아직 돌리지 않았다.
