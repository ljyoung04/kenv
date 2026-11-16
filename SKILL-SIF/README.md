# SKILL-SIF — 커널 취약점 분석 스킬 자가 개선 공간

[arXiv:2610.25705v1](https://arxiv.org/html/2610.25705v1) 의 SKILL-SIF(반복적 자가 개선
프레임워크)를 이 저장소에 맞게 옮긴 작업 공간이다. 실제 CVE의 수정 전 스냅샷에서
`vuln-discovery` 스킬이 취약점을 찾아내는지 채점하고, 실패한 실행에서 교훈을 뽑아
스킬 문서를 고친 뒤 다시 채점하는 과정을 반복한다.

운영 절차와 규칙은 `links/skills/skill-sif/SKILL.md` 가 기준이다. 이 문서는 구조 안내다.

## 루프

```text
오케스트레이터(세션)          서브에이전트 (SKILL-SIF 안에 배치)
──────────────────────       ─────────────────────────────────
dispatch detector  ───명령──▶ detector  × 케이스  (runs/…/<case>/ 에서 스킬 실행)
score              ◀──결과─── out/report.json, out/worklog.md
dispatch diagnoser ───명령──▶ diagnoser × 실패 케이스 (실행 기록 vs 정답 비교)
diagnose           ◀──결과─── diagnosis.json
어디를 고칠지 판단 → lessons/gen-NN.md
gen new → 스킬 사본 수정 → gen lint → 다시 dispatch detector …
정지 규칙 충족 → freeze → test 분할 실행·채점 → promote (유일한 외부 쓰기)
```

| 논문 | 이 공간 |
|---|---|
| 수정 커밋의 첫 부모로 만든 수정 전 스냅샷 (git 이력 없음) | `bin/sif case add --from` — 사용자가 준 소스를 그대로 사용 |
| 패치에서 뽑은 정답 (책임 구문, 포함 함수) | `truth.json` — 사용자의 `sol.md` 를 옮겨 적은 것 |
| CWE·함수·구문 3가지 검사, 모두 맞으면 fully correct | `bin/sif score` |
| 실패 궤적 진단 → failure lessons | diagnoser 서브에이전트 → `bin/sif diagnose` → `lessons/gen-NN.md` |
| SKILL.md 에 대한 표적 절차 수정 | `generations/gen-NN/skill/` 편집 + `bin/sif gen lint` |
| +G / −L 추적 | 채점 결과의 `vs_parent` |
| 최대 10라운드, 2라운드 연속 개선 없으면 조기 종료, 최고 세대 동결 | `config.json` 의 `max_rounds`, `patience`; `bin/sif freeze` |
| 보지 않은 100건의 독립 테스트 세트 | `cases/test/` — 동결된 세대에만 실행·채점 가능 |

논문과 다른 점: 논문은 수정 모델을 평가 모델과 분리했지만 여기서는 세션 모델이 수정한다.
대신 `gen lint` 가 케이스 고유 식별자(CVE, 정답 함수·파일명, 수정 제목)의 유입을 막고,
테스트 세트는 동결 전까지 잠겨 있다. 실패 분류 코드는 로컬 정의다
(`docs/failure-taxonomy.md`).

## 구조

```text
SKILL-SIF/
├── bin/sif              드라이버 (python3, 외부 의존성 없음)
├── agents/              서브에이전트 역할 지침 (detector.md, diagnoser.md)
├── config.json          정지 규칙, 채점 허용 오차, 실행 인자
├── state.json           기준 해시, 동결/반영 상태
├── links/               작업 공간 밖으로 나가는 유일한 통로 (심볼릭 링크)
│   ├── skills    → ../../.claude/skills          개선 대상 스킬 (promote 때만 쓰기)
│   └── AGENTS.md → ../../AGENTS.md
├── inbox/<source-version>/   사용자가 주는 소스와 정답 sol.md (탐지 중 잠김)
├── cases/{refine,test}/<id>/   case.json, truth.json, sol.md, src/ (탐지 중 잠김)
├── generations/gen-NN/  GEN.json + skill/ (세대별 스킬 사본, gen-00 = 기준선)
├── runs/gen-NN/<split>/<id>/   task.md, skill/, src/, out/, diagnosis.json
├── scores/gen-NN.<split>.json
├── lessons/gen-NN.md
├── archive/             promote 직전의 라이브 스킬 백업
└── docs/failure-taxonomy.md
```

## 케이스 넣기 (오프라인)

케이스의 소스와 정답은 사용자가 직접 준다. 로컬 커널 트리에 패치를 적용하거나 되돌려서
만들지 않는다.

```text
inbox/<source-version>/          취약한 소스 (폴더 자체 또는 그 안의 src/). 전체 트리든 필요한 파일만이든 무방
inbox/<source-version>/sol.md    이 소스에서 의도한 정답
```

```bash
bin/sif unlock --inbox                       # inbox 가 잠겨 있으면 먼저 연다
bin/sif case add --from inbox/<source-version> --split refine    # 또는 --split test
bin/sif case ls
```

- `sol.md` 는 `cases/<split>/<id>/sol.md` 로 복사되고, 저장되는 소스에서는 빠진다.
- `truth.json` 은 `sol.md` 안의 `경로:줄` 표기에서 뽑은 초안일 뿐이다. 오케스트레이터가
  `sol.md` 를 읽고 함수와 줄 범위를 옮겨 적은 뒤 `"reviewed": true` 로 바꿔야 실행할 수 있다.
- CWE 는 `--cwe` 로 주거나, `sol.md` 에 CWE 가 하나만 적혀 있으면 그것을 쓴다.
- 일부 파일만 줄 때는 대상 파일이 의존하는 헤더·호출 대상도 함께 넣는다.

## 정답 격리

분석 에이전트(detector)는 `inbox/` 와 `cases/` 를 읽을 수 없다.

- `dispatch detector` (및 `run`) 는 작업 디렉토리를 만든 뒤 `inbox/`, `cases/` 를 권한 000 으로
  잠그고 나서 프롬프트를 내준다. 작업 디렉토리에는 소스, 스킬 사본, `task.md` 만 들어간다.
- `score` 가 `cases/` 를 다시 연다. `inbox/` 는 `unlock --inbox` 전까지 잠긴 채로 둔다.
- 권한 잠금은 일반적인 읽기를 막는 장치이고 샌드박스는 아니다. 같은 사용자 권한의 에이전트가
  권한을 되돌리는 것까지는 막지 못하므로, 역할 지침에서 금지하고 흔적이 보이면 그 실행을 폐기한다.

## 현재 상태

`gen-00` (라이브 `vuln-discovery` 의 사본) 만 있고 케이스는 비어 있다. 드라이버는 합성
패치로 전 단계를 점검했다. 실제 탐지 실행은 아직 한 번도 돌리지 않았다.
