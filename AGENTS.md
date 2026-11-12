# AGENTS.md — agent guide for `kenv`

These instructions apply to the entire repository. `kenv` is a QEMU/KVM
Linux-kernel development environment with a profile (image) + VM (container)
model. Profile and VM state live on disk; the agent-facing CLIs are strict and
stateless.

## Agent invocation

Agents and automation call the scripts in `tools/` directly. The scripts
derive the repository path from their own location, so do **not** source
`tools/env.sh` first and do not rely on inherited `PRJ`, `PROFILE`, or `VM`
values. From outside this repository, use the absolute `/workspace/tools/...`
path.

Every profile-scoped command must pass `-p <profile>`. Every command targeting
a VM must pass both `-p <profile>` and `-v <vm>` before the subcommand.

```bash
# Discovery (no profile/VM flags)
/workspace/tools/vm.sh ls --json
/workspace/tools/vm.sh ps --json

# Profile-scoped operations
/workspace/tools/kernel.sh -p <p> --kctfconfig
/workspace/tools/kernel.sh -p <p> --olddefconfig
/workspace/tools/kernel.sh -p <p> --build -j 16
/workspace/tools/kernel.sh -p <p> --clang
/workspace/tools/vm.sh -p <p> run <task>_$(date +%s)

# VM-scoped operations
/workspace/tools/vm.sh -p <p> -v <v> ssh -- uname -r
/workspace/tools/vm.sh -p <p> -v <v> scp ./test.c vm:/root/test.c
/workspace/tools/vm.sh -p <p> -v <v> gdb
/workspace/tools/vm.sh -p <p> -v <v> attach
/workspace/tools/vm.sh -p <p> -v <v> log
/workspace/tools/vm.sh -p <p> -v <v> kill
/workspace/tools/vm.sh -p <p> -v <v> rm
```

The `--` before an SSH remote command is required. For SCP, mark the remote
side as `vm:/path`; prefix ambiguous local paths with `./`.

`tools/env.sh` and its `envlx`, `vm`, and `kernel` functions are interactive
user conveniences only. Do not use their remembered shell context in agent
work. In particular, examples such as `vm run a` in `commands.txt` are the
human flow; use the explicit commands above instead.

## Profiles and builds

Profiles live at `profiles/<p>/profile.sh` and are sourced as trusted shell
configuration. They require `ARCH`, `LLVM`, `FS`, and either:

- `KSRC` + `KOBJ` for a source/build profile; or
- `KIMAGE` for a prebuilt-kernel profile (optionally `KSRC` for GDB mapping).

`kernel.sh` build/config commands requiring source do not work with a
`KIMAGE`-only profile. A missing profile is not created by the stateless CLI.
For interactive setup, `source tools/env.sh --profile <p>` creates a template;
for automation, create and review `profiles/<p>/profile.sh` explicitly.

Image discovery and creation use:

```bash
/workspace/tools/fs.sh ls
/workspace/tools/fs.sh create <name> -a x86_64 -s 5120
```

Image creation uses sudo/debootstrap and mounts a disk image. Do not run it as
an incidental research step; use an existing image unless image creation is
part of the request.

## VM behavior

Name every agent-created VM `<task>_<unix-timestamp>`, with a descriptive task
made from letters, digits, `_`, or `-`. If a stopped directory already has that
name, use a new timestamp. Generic names such as `a`, `vm`, `vm1`, `test`, and
`debug` belong to users; never create, stop, remove, or reuse them.

`run` refuses to overwrite an existing VM directory. `kill` stops QEMU but
keeps logs and metadata. `rm` deletes a stopped VM directory and refuses a live
VM. Do not operate on a VM that this task did not create unless the user
explicitly identifies it as the target.

For `vm.sh ssh`, interpret exit status together with stderr diagnostics:

| rc | Meaning |
|---:|---|
| 0 | Connection and remote command succeeded |
| 251 | SSH unavailable (booting, network, sshd, hang, kdb, and so on) |
| 252 | `boot.log` contains panic/oops/BUG/GPF evidence |
| 1–254 | May be the remote command's own nonzero status |

A remote command can itself return 251 or 252, so do not classify the result
without the diagnostic message and `boot.log` evidence.

## Repository layout and state

```text
/workspace/
├── tools/                         CLI scripts and shell helpers
├── configs/                       kernel configs and `.clangd`
├── kernels/                       kernel sources and build artifacts
├── images/<name>/                 guest image and SSH keys
├── profiles/<p>/
│   ├── profile.sh                 static profile configuration
│   └── vms/<v>/
│       ├── vm.sh                  boot-time VM metadata
│       ├── vm.pid                 QEMU PID
│       └── boot.log               serial console log
├── agent/                         agent-generated research artifacts
├── user/                          user-owned material; preserve it
├── save/                          saved material; preserve it
├── commands.txt                   user and automation command recipes
└── README.md                      user-facing documentation
```

The current checkout may have no registered profiles. Discover them with
`/workspace/tools/vm.sh ls --json`; never guess a profile or VM from a previous
shell session.
`vm.pid` is checked against the matching QEMU command line rather than trusted
as an arbitrary live PID.

Keep task-generated PoCs, logs, patches, and notes under a dedicated
`agent/<task>/` directory. Kernel sources and build products stay under
`kernels/`. Preserve unrelated changes and all existing content under `user/`,
`save/`, and other tasks' artifact directories.

## Safety and legacy paths

- Run untrusted binaries, kernel PoCs, exploits, module-loading tests, and
  kernel-altering workloads only inside a task-owned VM, not on the host or in
  the development container (which shares the host kernel).
- Do not modify host kernel settings, modules, mounts, networking, services, or
  block devices unless the user explicitly requests that host-side action.
- Transfer research inputs with `vm.sh ... scp`. Use `--shared` only when the
  user has asked for a shared host directory.
- `envsetup.sh`, `run-vm.sh`, `ssh.sh`, and `scp.sh` are removed legacy entry
  points. Do not recreate or invoke them.
- Treat profile files as executable shell code and inspect untrusted profile
  content before sourcing it.

## Kernel research workflow

Vulnerability research runs as separate stages. Each stage has its own skill
in `.agents/skills/` (linked as `.claude/skills/` for Claude Code). Load only
the skill for the current stage.

| Stage | Skill | Gate to the next stage |
|---|---|---|
| Static audit and falsification | `vuln-discovery` | Revision, config, entry path, violated invariant, and falsification are recorded |
| Runtime confirmation in a task-owned VM | `dynamic-validation` | `DYNAMIC_CONFIRMED`, linked to the designated root cause |
| Root-cause fix and regression | `patch-generation` | Patch builds; reproducer, functional, and variant checks are recorded |
| Evidence cross-check and review bundle | `human-report` | — |
| Official kernelCTF service actions | `kctf-official-helper` | Needs explicit approval for each action |

- Run only the stages the user requested, in order. Finish and record each
  stage's gate before starting the next one.
- Source review alone does not authorize running code in a guest. Local
  validation does not authorize using the official service. A patch does
  not authorize submission or disclosure.
- Treat scanner, model, and earlier-agent output as hypotheses. Never raise a
  verdict above its evidence. Keep negative verdicts (`REJECTED`,
  `NOT_REPRODUCED`, `INFRA_BLOCKED`, `NEEDS_CONTEXT`) with their evidence.
- Each stage updates `agent/<research-name>/FINDINGS.md` with facts,
  verdicts, evidence paths, and SHA-256. A handoff carries Candidate-ID,
  Target-ID, exact revision and config, verdict, evidence, and open
  assumptions, not just a summary of the conversation.
- `user/tmp/` holds the earlier Codex-oriented copies of these rules for
  reference only.

## kernelCTF official tooling (`tools/kctf.sh`)

The official kernelCTF repo is checked out, user-owned and unmodified, under
`user/kctf/security-research/kernelctf/` (client, simulator, config checker,
submission checker, rules, style guide) and `user/kctf/kernel-research/`
(image_runner, kxdb_tool, rop_generator, libxdk). Do not edit anything under
`user/`. Drive these tools only through the wrapper `tools/kctf.sh`, which
derives paths from its own location (override with `KCTF_DIR=`).

```bash
tools/kctf.sh paths                       # resolved paths + dependency/kvm check
tools/kctf.sh rules | style | faq         # print local rules.md / style_guide.md / faq.md
tools/kctf.sh check-config <target.config> user/kctf/security-research/kernelctf/kernel_configs/<target>.config
tools/kctf.sh sim <release-name> [--root] # boot a release in a LOCAL VM (no official server)
tools/kctf.sh repro-summary <repro.log>
tools/kctf.sh verify <exploit_path...>    # local build+verify on upstream/stable
tools/kctf.sh info                        # read-only query of active targets (contacts official server)
tools/kctf.sh lpe-test  <exploit> [--local] [cli args...]
tools/kctf.sh vuln-test <exploit> [--local] [cli args...]
tools/kctf.sh evaluate  <exploit> --researcher-token <T> [cli args...]
```

Required-config fragments live in
`user/kctf/security-research/kernelctf/kernel_configs/` (`hardened-v1.config`,
`lts-6.12-v2.config`, ...); pass the one matching the target as the second
`check-config` argument.

Safety gate (matches the `kctf-official-helper` skill and "Safety and legacy
paths" above): `lpe-test`/`vuln-test`/`evaluate` run an exploit on the OFFICIAL
Google service and are **refused** unless the operator opts in with
`KCTF_CONFIRM_OFFICIAL=1` (or passes `--local` to target a local server/VM).
The gate is a backstop only: an agent must still obtain the user's explicit,
per-attempt approval before any official-service action, exactly as the
`kctf-official-helper` stage requires. Local/offline subcommands
(`check-config`, `check-submission`, `repro-summary`, `sim`, `verify`, docs,
`paths`) run without the gate.

## Response format

Write repository paths in backticks. For a location with a line number, keep
the path and line together inside the backticks, for example
`tools/vm.sh:120`.

For additional usage details, consult `commands.txt`, `README.md`, and each
CLI's `--help` output. Prefer the explicit automation recipes in
`commands.txt` over the interactive shell-helper examples.
