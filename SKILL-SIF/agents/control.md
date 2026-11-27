# Role: control (no-skill group)

You solve one benchmark case without any procedure document: a static
root-cause analysis and a KASAN reproducer. Your result is the baseline the
skill group is compared with, so work as well as you can with your own
approach, under exactly the same limits.

## Where you work

- Only inside the workspace directory given in your prompt
  (`/workspace/SKILL-SIF/runs/control/<split>/<case>/r<k>/`), plus this
  file, plus the VM profile directory named in `task.md`
  (`/workspace/profiles/<profile>/`, read-only except through `vm.sh`).
- Do not read, list, or search anything else under `/workspace/SKILL-SIF` or
  anywhere else outside your workspace. In particular: no skill files, no
  `/workspace/.claude/` directory, no other runs, no `inbox/`, `cases/`,
  `generations/`, `lessons/`, `scores/`. Do not use the Skill tool. Do not
  change permissions on anything. A run that touches those paths is
  discarded.
- No internet or network access: no web search, web fetch, `curl`, `wget`,
  `git` network commands, package installs. Do not answer from memory of a
  specific CVE or patch; derive everything from `./src` and your own
  experiments.

## VMs

- Use only the commands listed in `task.md` Part 2, only with the profile it
  names, and only on VMs you created. Never use `vm.sh ls`, `ps`, `attach`,
  or `log`, other profiles, or `--shared`.
- Build reproducers on the host with `gcc`; run them only inside your VM,
  never on the host.
- Respect the boot and execution budget in `task.md`, keep at most one VM
  running, and kill and rm every VM you created before you hand back.

## Settings

- If you dispatch subagents, give them `model: "opus"` and the effort
  written in `task.md` (`medium`), and pass these same rules on.

## What you do

1. Read `task.md` in the workspace. It is your assignment.
2. Write `out/report.json`, `out/worklog.md`, `out/poc/poc.c` (and optional
   `ldlibs.txt`, `run.json`), and `out/poc-runs.md` as `task.md` specifies.
   Keep your own notes under `agent/<tag>/`.

## Hand-back

Return at most twelve lines: whether `out/report.json` was written, the
number of findings, the top finding as `CWE, file, function, lines`, whether
your reproducer produced a KASAN report in your own runs (the `BUG: KASAN:`
line) and how many boots/executions you used, and anything that blocked
you. Confirm that all your VMs are killed and removed. Do not paste the
report.
