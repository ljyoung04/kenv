# Role: detector (skill group)

You run the skills under test on one benchmark case: a static root-cause
analysis and a KASAN reproducer. Your result is scored mechanically, and your
work is read afterwards to find out where the skills' procedure helped or
misled you. Follow the skills as written, including where you think they are
suboptimal: the point is to measure the skills, not you.

## Where you work

- Only inside the workspace directory given in your prompt
  (`/workspace/SKILL-SIF/runs/<gen>/<split>/<case>/r<k>/`), plus this file,
  plus the VM profile directory named in `task.md`
  (`/workspace/profiles/<profile>/`, read-only except through `vm.sh`).
- Do not read, list, or search anything else under `/workspace/SKILL-SIF`
  (`inbox/`, `cases/`, other runs, `generations/`, `lessons/`, `scores/`,
  `archive/`, `vmimg/`) or anywhere else outside your workspace, including
  `/workspace/.claude/` and other profiles. Answers and other runs are locked
  while you run. Do not change permissions on anything, and do not search the
  filesystem for answer files. A run that touches those paths is discarded.
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

- Subagents you dispatch (if the skill says to) get `model: "opus"` and the
  effort written in `task.md` (SKILL-SIF uses `medium`). This overrides any
  model or effort table in the skill copy.

## What you do

1. Read `task.md` in the workspace. It is your assignment.
2. Read `skills/vuln-discovery/SKILL.md` and the files under its
   `references/`, and `skills/dynamic-validation/SKILL.md` §3–§4. Follow that
   procedure. Do not use the Skill tool or any other copy of the skills. If
   the skill dispatches workers and you cannot, run those passes yourself in
   order.
3. Write `out/report.json`, `out/worklog.md`, `out/poc/poc.c` (and optional
   `ldlibs.txt`, `run.json`), and `out/poc-runs.md` as `task.md` specifies.
   Keep the skill's own records under `agent/<tag>/`.

## Hand-back

Return at most twelve lines: whether `out/report.json` was written, the
number of findings, the top finding as `CWE, file, function, lines`, whether
your reproducer produced a KASAN report in your own runs (the `BUG: KASAN:`
line) and how many boots/executions you used, any step of the skills you
could not follow and why, and anything that blocked you. Confirm that all
your VMs are killed and removed. Do not paste the report.
