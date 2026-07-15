# linux-env

QEMU/KVM을 중심으로 구축한 간결한 Linux 커널 개발 및 디버깅 환경으로,
Docker 스타일의 **profile + vm** 모델을 사용합니다.

> *profile*을 한 번 정의한 뒤(사용할 커널, 루트 파일 시스템, 아키텍처)
> 그 위에 이름이 있는 *VM*을 띄워 부팅, SSH, gdb, 퍼징, 익스플로잇 작업
> 등에 사용합니다. 이제 모든 셸에서 `SRC=…`, `OBJ=…`, `SSH_PORT=…`를
> 일일이 들고 다닐 필요가 없습니다.

---

## 필요한 이유

다음 작업을 자주 한다면:

- 여러 Linux 커널 버전을 나란히 빌드하고,
- KVM 가속을 사용해 QEMU에서 원하는 커널을 부팅하고,
- 실행 중인 게스트에 SSH/scp/gdb로 접속하고,
- 여러 게스트를 동시에 실행해 두는 경우,

…이 저장소는 흔히 사용하는 임시방편의 셸 스크립트를 작고 예측 가능한
인터페이스로 대체합니다:

| 원하는 작업                 | 실행할 명령                                      |
|-----------------------------|--------------------------------------------------|
| 커널/파일 시스템 조합 정의 | `profiles/<name>/profile.sh` 편집(템플릿 자동 생성) |
| 해당 조합 환경 진입         | `source scripts/env.sh --profile <name>`         |
| 해당 환경에서 새 VM 부팅    | `scripts/vm.sh run <vm_name>`                    |
| 실행 중인 VM 접속           | `scripts/vm.sh ssh`                              |
| 커널 빌드                   | `scripts/kernel.sh --build`                      |
| 실행 중인 모든 항목 확인    | `scripts/vm.sh ps`                               |

---

## 개념

용어 체계는 Docker에서 그대로 가져왔습니다:

| Docker            | linux-env             | 디스크상의 위치                       |
|-------------------|-----------------------|---------------------------------------|
| 이미지(불변)      | **profile**           | `profiles/<p>/profile.sh`             |
| 컨테이너          | **vm**                | `profiles/<p>/vms/<v>/`               |
| `docker images`   | `vm.sh ls`            | —                                     |
| `docker ps`       | `vm.sh ps`            | —                                     |
| `docker run`      | `vm.sh run <vm_name>` | —                                     |

profile은 작은 셸 파일이며 두 가지 방식이 있습니다:

- **유형 A — 소스에서 빌드.** `KSRC`(커널 트리)와
  `KOBJ`(빌드 디렉터리)를 설정합니다. `scripts/kernel.sh --build`가
  bzImage를 생성합니다.
- **유형 B — 미리 빌드된 bzImage.** `KIMAGE`를 직접 설정합니다.
  CTF/릴리스 이미지에 유용합니다. `KSRC`는 선택 사항입니다
  (gdb 소스 매핑에만 사용).

두 유형 모두 `ARCH`, `LLVM`, `FS`(루트 파일 시스템 이미지 디렉터리)가
필요합니다.

---

## 빠른 시작

### 1. 모든 셸에서 도우미 사용하기(선택 사항이지만 권장)

`~/.bashrc`에 다음 한 줄을 추가합니다:

```bash
envlx() { source /path/to/linux-env/scripts/env.sh "$@"; }
```

`envlx`를 처음 호출하면 `scripts/env.sh`를 `source`합니다. 이 스크립트는
프로젝트 전역 변수(`$PRJ`, `$SCRIPTS`, `$CONFIGS`, `$IMAGES`, `$SHARE`,
`$SYZKALLER`)를 내보내고, `vm`/`lsfs`/`setfs`/`mkfs`/`vmhttp` 도우미를
정의하며, 위의 임시 함수를 실제 `envlx`로 덮어씁니다. 그다음부터는
모든 셸에서 `envlx`와 `vm`을 사용할 수 있습니다.

셸 도우미를 원하지 않는다면 필요할 때 `source scripts/env.sh`를 직접
실행하면 됩니다. 아래의 모든 예시는 어느 방식으로든 작동합니다.

### 2. 첫 profile 정의하기

```bash
envlx --profile lts-6.12
# → "Profile 'lts-6.12' does not exist."
# → "Creating template at: .../profiles/lts-6.12/profile.sh"
# → "Edit it, then run: source $SCRIPTS/env.sh --profile lts-6.12"
$EDITOR $PRJ/profiles/lts-6.12/profile.sh
```

유형 A 예시(소스에서 빌드):

```sh
export ARCH=x86_64
export LLVM=1
export FS="$IMAGES/x64"
export KSRC="$PRJ/kernels/linux-6.12.y"
export KOBJ="$KSRC/build/debug"
```

유형 B 예시(릴리스 bzImage 사용):

```sh
export ARCH=x86_64
export LLVM=1
export FS="$IMAGES/x64"
export KIMAGE="$PRJ/kctf/releases/lts-6.12.79/bzImage"
```

### 3. 커널 빌드하기(유형 A)

```bash
envlx --profile lts-6.12
kernel.sh --olddefconfig
kernel.sh --build               # 기본값은 -j 16, -j N으로 변경 가능
kernel.sh --clang               # 선택 사항: compile_commands.json + .clangd
```

kernelctf의 기본 config에서 시작하려면:

```bash
kernel.sh --kctfconfig          # cp $CONFIGS/kernelctf.config $KOBJ/.config
kernel.sh --olddefconfig
kernel.sh --build
```

### 4. VM을 부팅하고 접속하기

```bash
vm run a                        # 'a'라는 이름의 VM 부팅
                                # 출력 마지막 줄: "Run: envlx --vm a"
envlx --vm a                    # SSH_PORT, GDB_PORT를 현재 셸에 불러오기
vm ssh                          # 게스트에 대화형 SSH로 접속
vm ssh uname -a                 # 일회성 원격 명령
vm log                          # $VM/boot.log를 실시간으로 출력
```

### 5. 두 번째 VM을 동시에 실행하기

```bash
vm run b                        # 서로 다른 SSH/GDB 포트 쌍을 자동 할당
vm ps                           # 'a'와 'b' 모두 표시
envlx --vm b                    # 셸 컨텍스트를 'b'로 전환
vm ssh hostname
```

### 6. 종료 및 삭제하기

```bash
vm kill                         # QEMU 중지, 나중 분석을 위해 $VM/boot.log 유지
vm rm                           # $VM 디렉터리를 완전히 삭제
                                # (VM이 아직 실행 중이면 거부)
```

---

## 참조

### 스크립트

| 스크립트 | 용도 |
|----------|------|
| `scripts/env.sh`     | `source` 전용 진입점. `--profile`/`--vm`/`--reset`을 처리하고 전역 변수를 설정하며 도우미를 정의합니다. |
| `scripts/vm.sh`      | VM 수명 주기: `ls`/`ps`/`run`/`ssh`/`scp`/`gdb`/`attach`/`kill`/`rm`/`log`. |
| `scripts/kernel.sh`  | 커널 빌드/config: `--menuconfig`/`--olddefconfig`/`--kctfconfig`/`--build [-j N]`/`--clang`. |
| `scripts/envsetup.sh`, `scripts/run-vm.sh` | 참조용으로 유지하는 레거시 진입점. 새 코드는 이 파일들을 호출하지 않습니다. |

### 파일 시스템 이미지

```bash
lsfs                            # $IMAGES 아래에서 사용 가능한 이미지 목록
setfs <name>                    # 현재 셸의 $FS를 $IMAGES/<name>으로 설정
mkfs <name> [-a arch] [-s MB]   # 새 이미지 생성(debootstrap 기반)
```

`$FS`는 일반적으로 profile의 일부로 `profile.sh`에 정의하지만, `setfs`는
일회성 실험에 유용합니다.

### tmux 연동

각 VM은 백그라운드의 tmux 세션/창 안에서 실행됩니다:

- 세션 이름: `vms_<profile_name>`(profile 이름의 `.`과 `:`은 `_`로
  바뀝니다. tmux가 이 문자를 대상 구분자로 사용하기 때문입니다)
- 창 이름: `<vm_name>`

```bash
vm attach                       # tmux attach -t vms_<p>:<vm_name>
```

### VM별 상태 파일

`$PROFILE/vms/<vm_name>/` 아래:

| 파일 | 내용 |
|------|------|
| `vm.sh`    | `source` 가능: `SSH_PORT`, `GDB_PORT`, `VM_KERNEL_IMAGE`, `VM_FS`, … |
| `vm.pid`   | QEMU PID — 실행 여부를 판단하는 유일한 기준 |
| `boot.log` | 직렬 콘솔 출력 |
| `qemu.mon` | QEMU 모니터 Unix 소켓 |

`vm.sh ps`는 `vm.pid`를 읽고 `/proc/$PID`를 확인해 실행 여부를 판단합니다.
종료된 디렉터리는 자동으로 정리하지 않으므로 충돌을 사후 분석할 수 있습니다.
명시적으로 정리하려면 `vm.sh rm`을 사용합니다.

### JSON 출력

스크립트/에이전트용:

```bash
vm ls --json
vm ps --json
```

### 다른 셸에서 컨텍스트 복원하기

인자 없이 `envlx`를 실행하면 현재 범위를 출력하고, 다른 터미널에 복사해
붙여넣을 수 있는 `Restore:` 줄로 끝납니다:

```
Restore: source $SCRIPTS/env.sh --profile lts-6.12 --vm a
```

---

## 디렉터리 구조 개요

```
linux-env/
├── kernels/<name>/             # clone하거나 압축을 푼 커널 소스 트리
├── images/<name>/bookworm.img  # 루트 파일 시스템 이미지(mkfs / create-image.sh)
├── profiles/<name>/            # profile 정의
│   ├── profile.sh              # 정적 config(env.sh에서 source)
│   └── vms/<vm_name>/          # VM별 동적 상태(vm.sh, vm.pid, boot.log)
├── configs/                    # 커널 config, .clangd 템플릿
├── share/                      # 호스트↔게스트 9p 공유 디렉터리
├── syzkaller/                  # syzkaller 작업 공간
├── scripts/
│   ├── env.sh, vm.sh, kernel.sh    # 주요 진입점
│   ├── envsetup.sh, run-vm.sh      # 레거시(참조 전용)
│   ├── ssh.sh, scp.sh              # vm.sh가 사용하는 내부 도우미
│   ├── shell-init.sh               # 선택 사항인 bashrc 임시 함수
│   └── create-image.sh, .common.sh
├── commands.txt                # 주석이 달린 작업 흐름 예시
├── README.md                   # 이 파일
└── CLAUDE.md                   # 에이전트용 운영 가이드
```

---

## Docker(선택 사항)

호스트에 LLVM-19/QEMU/debootstrap을 설치하고 싶지 않다면, 이 저장소에서
모든 도구가 미리 설치된 개발 컨테이너를 제공합니다.

```bash
./init.sh                       # .env 생성(UID/GID 감지, SSH 포트)
docker compose up -d
docker compose exec -u kenv-$(whoami) kenv bash
```

컨테이너 안에서도 위의 profile/vm 작업 흐름은 동일합니다. 프로젝트
디렉터리는 `/workspace`에 바인드 마운트됩니다.

컨테이너에 미리 설치된 도구:

- LLVM/Clang-19, GDB 17.1([bata24/gef][gef] 포함), tmux, jq
- fzf, ripgrep, fd, bat, eza, tree, zoxide
- htop, strace, ltrace, nano, openssh-server

[gef]: https://github.com/bata24/gef

### SSH 연결 경로

```
로컬 머신  ─ssh→  서버  ─docker exec→  컨테이너  ─vm.sh ssh→  QEMU 게스트
```

컨테이너 SSH 포트(호스트 → 컨테이너)는 `.env`의 `SSH_PORT`로 설정할 수
있습니다(기본값 2222, `init.sh`가 자동 선택).

---

## 참고 사항

- `scripts/envsetup.sh`와 `scripts/run-vm.sh`는 레거시 "단일 전역 VM"
  작업 흐름의 참조용으로 유지됩니다. 필요하면 여전히 독립적으로 작동하지만,
  새 작업 흐름에서는 호출하지 않습니다. 향후 삭제할 예정입니다.
- 저장소 루트의 `prompt_init`, `prompt_output`, `prompt_final`에는 현재의
  profile/vm 모델을 만들게 된 설계 근거가 기록되어 있습니다. 작업 흐름
  문서는 아니므로 *왜* 이렇게 설계했는지 궁금할 때만 읽으세요.
- `commands.txt`는 에이전트용 실전 예제 치트 시트입니다.

---

## 감사의 말

QEMU/KVM, debootstrap, LLVM/Clang, tmux, gdb(+ bata24/gef) 등 표준 도구를
기반으로 만들었습니다. profile/vm CLI 형태는 Docker를 느슨하게 본떠
설계했습니다.
