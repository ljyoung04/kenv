# kenv

QEMU/KVM 기반 Linux 커널 개발·디버깅 환경입니다. **profile**은 커널과
파일 시스템 설정이고, **VM**은 해당 profile로 부팅한 개별 게스트입니다.

실제 스크립트 경로는 `tools/`입니다. 모든 CLI는 자신의 위치로 프로젝트
경로를 계산하므로, 실행 디렉터리나 이전 셸의 환경 변수에 의존하지 않습니다.

## 두 가지 사용 방식

사용자는 선택한 profile/VM을 기억하는 셸 함수를 사용할 수 있습니다:

```bash
source tools/env.sh
envlx --profile lts-6.12
kernel --build -j 16
vm run a
envlx --vm a
vm ssh -- uname -r
```

에이전트와 자동화는 대상이 명시된 CLI를 직접 호출합니다. `env.sh`를
source할 필요가 없으며, 다른 디렉터리에서는 절대 경로를 사용합니다:

```bash
/workspace/tools/vm.sh ls --json
/workspace/tools/vm.sh ps --json
/workspace/tools/kernel.sh -p lts-6.12 --build -j 16
/workspace/tools/vm.sh -p lts-6.12 run research_$(date +%s)
/workspace/tools/vm.sh -p lts-6.12 -v <vm_name> ssh -- uname -r
/workspace/tools/vm.sh -p lts-6.12 -v <vm_name> scp ./test.c vm:/root/test.c
```

`vm.sh`와 `kernel.sh`는 상속된 profile/VM 설정을 초기화하고 명시된
`-p`/`-v`로 설정을 읽습니다. `-p`, `-v`는 하위 명령 앞에 둡니다.
SSH 원격 명령 앞에는 `--`가 필요합니다. `scp`는 로컬 경로와 `vm:/경로`
한 쌍을 받습니다. `:`이나 `-`로 혼동될 수 있는 로컬 이름에는 `./`를 붙입니다.

## 빠른 시작

### 1. 셸 도우미 등록하기 (선택)

`~/.bashrc` 또는 `~/.zshrc`에 다음 함수를 넣습니다. 제공되는 Docker의
Bash 설정에는 `/workspace/tools/env.sh` 경로로 등록되어 있습니다.

```bash
envlx() { source /path/to/kenv/tools/env.sh "$@"; }
```

`envlx`를 처음 실행하면 `vm`, `kernel`, `connect`, `lsfs`, `setfs`, `mkfs`, `vmhttp`
함수도 정의됩니다. `env.sh`는 대화형 편의 계층이며 CLI 실행의 전제 조건이
아닙니다. `PRJ`, `SCRIPTS`, `CONFIGS`, `IMAGES`, `SHARE`, `SYZKALLER`는
항상 현재 저장소 경로로 설정됩니다. 기존 이름인 `SCRIPTS`는 `tools/`를 가리킵니다.

### 2. profile 정의하기

```bash
envlx --profile lts-6.12          # 없으면 템플릿 생성 후 종료
$EDITOR "$PRJ/profiles/lts-6.12/profile.sh"
```

소스에서 빌드하는 profile:

```bash
export ARCH=x86_64
export LLVM=19
export FS="$IMAGES/x64"
export KSRC="$PRJ/kernels/linux-6.12.y"
export KOBJ="$KSRC/build/debug"
```

미리 빌드된 이미지로 부팅하는 profile:

```bash
export ARCH=x86_64
export LLVM=19
export FS="$IMAGES/x64"
export KIMAGE="$PRJ/releases/example/bzImage"
# 선택: GDB 소스 매핑에 사용할 KSRC
```

profile은 신뢰하는 사용자가 작성한 셸 설정 파일입니다. source되므로 임의의
외부 파일을 profile로 사용하지 않습니다. CLI만 사용할 때는
`profiles/<name>/profile.sh`를 직접 생성해도 됩니다.

선택 설정은 `CROSS_COMPILE`, `SMP`, `MEM`, `EXTRA_CMDLINE`입니다.
profile 전환이나 CLI 호출 때 이전 값이 남지 않도록 초기화합니다.
현재 VM 실행기는 x86_64 QEMU/KVM을 사용합니다. arm64 커널 빌드나 이미지
생성이 가능하더라도 arm64 VM 부팅을 지원한다는 뜻은 아닙니다.

### 3. 커널 빌드하기

```bash
envlx --profile lts-6.12
kernel --kctfconfig              # configs/kernelctf.config를 KOBJ/.config로 복사
kernel --olddefconfig
kernel --build -j 16
kernel --clang                  # compile_commands.json, .clangd
```

`kernel --menuconfig`도 지원합니다. `kernel -p other --build`처럼 한 번만
다른 profile을 지정할 수 있으며 현재 셸의 선택은 바뀌지 않습니다.

### 4. VM 실행·접속·종료하기

```bash
vm run a
envlx --vm a
vm ssh
vm ssh -- uname -r
vm scp ./test.c vm:/root/test.c
vm scp vm:/root/result.txt ./result.txt
vm gdb
vm log
vm attach
vm ps
vm kill                         # QEMU 종료, 로그·메타데이터 보존, 셸 VM 선택 해제
vm rm a                         # 중지된 VM 디렉터리 삭제; 이름을 명시해야 함
```

VM 이름이 이미 존재하면 `run`은 덮어쓰지 않고 실패합니다. 새 이름을 쓰거나
필요한 산출물을 보존한 뒤 명시적으로 `rm`합니다. `kill`과 `rm`은 PID가
해당 VM의 QEMU인지 검사하며, PID가 다른 살아 있는 프로세스를 가리키면 거부합니다.

`vm -p other -v b ssh -- uname -r`는 한 번만 다른 VM에 접속합니다.
다른 profile을 `-p`로 지정할 때 현재 profile의 VM 이름을 자동 재사용하지
않으므로, VM 작업에는 `-v`도 지정해야 합니다.

`run` 옵션은 `--kaslr`, `--shared`(9p 공유), `--android`입니다.
취약점 연구 파일은 `vm scp`로 옮깁니다. `vmhttp`는 선택한 로컬 디렉터리를
HTTP로 제공하는 별도 편의 함수입니다.

SSH 종료 코드는 원격 명령의 코드를 유지합니다. SSH가 255로 실패하면
`boot.log`를 확인하여 251(접속 불가) 또는 252(panic/oops 흔적)를 반환합니다.
원격 명령도 251/252를 반환할 수 있으므로 진단 메시지와 함께 해석합니다.

### 5. 파일 시스템 이미지 관리하기

```bash
./tools/fs.sh ls
./tools/fs.sh create x64 -a x86_64 -s 5120
# 셸 도우미로 같은 기능 호출:
lsfs
mkfs newimg -a x86_64 -s 5120
```

생성에는 sudo와 debootstrap이 필요하며 디스크 이미지 마운트를 수행합니다.
기존 이미지 디렉터리는 재사용하지 않습니다. 실패하면 부분 산출물을 보존합니다.
기본 배포판은 bookworm이며, VM은 `bookworm.img`와 `bookworm.id_rsa`를 사용합니다.
다른 배포판은 `-d`로 생성할 수 있지만 현재 VM 실행기의 대상은 아닙니다.

`setfs <name>`과 `mkfs`의 자동 선택은 현재 셸의 `FS`만 변경합니다.
`mkfs`의 기본 아키텍처는 현재 profile의 `ARCH`이며 `-a`로 바꿀 수 있습니다.
VM에서 사용할 이미지를 변경하려면 **profile.sh의 FS를 수정**해야 합니다.
이미 실행 중인 VM은 부팅 당시 기록한 이미지·소스 경로로 접속합니다.

## 스크립트 구성

`connect`는 `tools/server_cert.pem`으로 TLS 서버에 접속합니다 (`socat` 필요).
제공되는 Bash 설정에서는 바로 사용할 수 있고, 다른 셸에서는
`source tools/env.sh`로 등록합니다. profile/VM 선택은 필요하지 않습니다.

```bash
connect                         # 기본 KernelCTF 서버
connect hostname:port           # 접속 대상 지정
```

| 파일 | 역할 |
|---|---|
| `tools/.common.sh` | 전역 경로 초기화, 진단, 이름 검증, profile/VM 로딩·초기화 |
| `tools/env.sh` | 선택 사항인 Bash/zsh 컨텍스트와 사용자용 단축 함수 |
| `tools/vm.sh` | VM 목록·실행·SSH·SCP·GDB·종료·삭제 |
| `tools/kernel.sh` | 커널 config·빌드·clang 도구 설정 |
| `tools/connect.sh` | 동봉된 인증서를 사용하는 TLS 접속 (`connect`) |
| `tools/fs.sh` | 이미지 목록·생성 CLI |
| `tools/create-image.sh` | Debian 이미지 생성 백엔드; 빈 작업 디렉터리에서 직접 사용 가능 |
| `tools/extract-vmlinux.sh` | 커널 이미지에서 vmlinux 추출 |
| `tools/repo-apply.py` | AOSP `repo diff` 적용·dry run |
| `tools/tracer.sh` | 게스트에서 source하는 ftrace 도우미 |
| `tools/gdb/race_debug.gdb` | GDB 디버깅 명령 모음 |

중복된 `envsetup.sh`, `run-vm.sh`, `ssh.sh`, `scp.sh`는 제거했습니다.

| 이전 호출 | 대체 호출 |
|---|---|
| `source scripts/env.sh` | `source tools/env.sh` (대화형 셸에서만 필요) |
| `source .../envsetup.sh` | `source tools/env.sh --profile <p>` |
| `run-vm.sh` | `tools/vm.sh -p <p> run <v>` |
| `ssh.sh ...` | `tools/vm.sh -p <p> -v <v> ssh -- ...` |
| `scp.sh ...` | `tools/vm.sh -p <p> -v <v> scp ./file vm:/path` |

자동화 지침에도 “매 Bash 호출마다 env.sh를 source”하는 규칙이 필요하지 않습니다.
명시적 CLI와 `-p`/`-v`를 사용하면 됩니다.

## 상태와 디렉터리

```text
kenv/
├── tools/                     # CLI와 셸 도우미
├── kernels/<name>/            # 커널 소스
├── images/<name>/             # bookworm.img, bookworm.id_rsa
├── profiles/<name>/profile.sh # 정적 설정
│   └── vms/<vm>/              # vm.sh, vm.pid, boot.log, qemu.mon
├── configs/                   # 커널 config와 .clangd
├── share/                     # 연구 산출물과 전송할 파일
├── tests/test_cli.py          # 격리된 CLI 회귀 테스트
└── commands.txt              # 호출 예시
```

VM은 `vms_<profile>` tmux 세션의 `<vm>` 창에서 실행됩니다. profile 이름의
`.`은 tmux 세션 이름에서 `_`로 바뀝니다. VM 생존 여부는 PID와 해당 QEMU의
명령행을 함께 검사합니다. `vm.sh ls --json`, `vm.sh ps --json`은 JSON을 출력합니다.

인자 없는 `envlx`는 디스크의 설정을 다시 읽고 현재 컨텍스트와 다른 셸에
복사할 수 있는 복원 명령을 출력합니다. `envlx --reset`은 선택을 해제합니다.

## 검증

```bash
python3 -m unittest discover -s tests -v
```

테스트는 임시 저장소와 대체 명령을 사용합니다. 실제 VM, SSH 접속, 커널 빌드,
sudo, 이미지 마운트는 실행하지 않습니다.

## Docker (선택)

```bash
./init.sh
docker compose up -d
docker compose exec -u kenv-$(whoami) kenv bash
```

프로젝트는 `/workspace`에 마운트됩니다. 컨테이너 SSH 포트는 `.env`의
`SSH_PORT`로 설정합니다. 컨테이너에는 LLVM/Clang-19, QEMU, debootstrap,
GDB([bata24/gef](https://github.com/bata24/gef)), tmux, jq와 개발 도구가 포함됩니다.
