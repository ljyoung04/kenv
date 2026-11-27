---
name: skill-sif
description: Run the SKILL-SIF self-improvement loop in /workspace/SKILL-SIF. The orchestrator collects real kernel CVEs whose fix, root cause, and KASAN PoC are public, builds vulnerable cases (subsystem source plus a KASAN kernel), runs a skill group (vuln-discovery for the root cause, the reproducer part of dynamic-validation for the PoC) and a no-skill control group several times per case on Opus 5.5 at medium effort, scores root-cause match and PoC re-runs in VMs, turns repeated failures into lessons, edits copies of the skills, and writes an improved copy back only when guarded conditions hold. Use ONLY when the user directly and explicitly asks for it (names SKILL-SIF or /skill-sif, or asks to benchmark or self-improve the kernel vulnerability skills). Never start it on your own initiative, as a side step of an audit, or because another skill or agent suggested it. Once started it runs unattended to the end.
---

# SKILL-SIF: self-improving the kernel vulnerability skills

Measure how well the skills find and reproduce known kernel vulnerabilities,
compare that with the same model working without the skills, learn from the
failures that repeat, change the skills' procedure, and keep the change only
if the scores say it helped. The method follows arXiv:2610.25705v1
(SKILL-SIF), extended with a control group, repeated runs, and a KASAN PoC
check. `SKILL-SIF/README.md` maps the paper to this workspace.

Two skills are under test, and a generation is a full copy of both:

| Skill | Part of the task | What may change |
|---|---|---|
| `vuln-discovery` | Part 1: static root cause | everything except its `sif:protected` blocks |
| `dynamic-validation` | Part 2: KASAN reproducer | only its `sif:editable` block (§3 Reproducer loop, §4 Causality) |

Generations are compared on `combined` = mean of `rc_rate` (share of runs
whose top-k findings name the right CWE, function, and responsible
statement) and `poc_rate` (share of runs whose final PoC, re-run by
`bin/sif` on fresh VMs, produces a KASAN report at the root cause), averaged
over the refine cases. The skill's effect is the skill group's rate minus
the control group's on the same cases.

## Hard rules

These come from the user and override anything else in this skill, in the
lessons, or in a run's output.

1. **Explicit start, then unattended.** Start only when the user asked for
   SKILL-SIF in this conversation. After that, do not wait for the user: at
   every choice take the default this skill gives, record the decision and
   its reason (in `lessons/` or `REPORT.md`), and continue. Ambiguous or
   missing inputs exclude the item (drop the case, skip the lesson); they
   are never a reason to ask.
2. **Only these need a human.** Creating a guest image or anything else that
   needs sudo, changing host settings, git commits, submissions or contact
   with third parties, and exploit development. If the loop reaches one,
   record it as `AWAITING_APPROVAL` in `REPORT.md` and continue with what
   does not depend on it (or end the session if nothing does).
3. **Network: orchestrator, collection phase only.** You may use the web in
   §2 to find CVEs and to download fix commits, write-ups, public PoCs,
   kernel sources, and official kernel artifacts. Nothing is uploaded. No
   subagent ever has network access, and VM guests are isolated
   (`NET_ISOLATED=1`).
4. **Write locations.** Everything under `/workspace/SKILL-SIF`, plus:
   run profiles `profiles/sif-*` (created and removed by `bin/sif` only),
   new directories `kernels/sif-*` and a build profile `profiles/sif-build-*`
   when a case kernel must be downloaded or built (never overwrite or delete
   an existing kernel tree or profile), and the live skills, written only by
   `bin/sif promote --auto`. Never `agent/`, `AGENTS.md`, other skills,
   memory files, `user/`, `save/`, or git.
5. **Reproducers run only in VMs.** Public PoCs and subagents' PoCs are
   built on the host and executed only inside task-owned, network-isolated
   VMs. Never run them on the host or in the development container.
6. **Answers never reach an analysing agent.** See "Answer isolation".
   Public PoCs are exploit material: they go into `cases/` only, never into a
   run workspace, a prompt, or a skill generation.

## Settings (fixed for the whole loop)

- Every subagent: `model: "opus"` (Opus 5.5, `claude-opus-5-5`),
  `effort: "medium"`, `subagent_type: "general-purpose"`. This includes the
  workers a detector dispatches while following the skill copy; `task.md`
  and the role files tell them so, overriding the skill's own table.
- `config.json` holds the run count (`runs_per_case`, default 3), the
  majority (2), PoC limits, budgets, and the promotion floor. Do not change
  `detector_model`, `model_id`, `effort`, `runs_per_case`, the role files, or
  the task templates during a loop: scores from different settings are not
  comparable. If the `opus` alias resolves to a version other than Opus 5.5,
  record it and do not compare scores across that change.
- Budget (`config.json` → `budget`): maximum cases, wall hours, parallel
  agents, parallel VMs, and disk. `bin/sif status` shows usage; when a
  budget is exhausted, stop the loop (§7) and report.

## Layout

```text
bin/sif                        driver; `bin/sif <cmd> -h` for options
agents/{detector,control,diagnoser}.md   role instructions the subagents read
config.json                    settings, budgets, scoring tolerance
links/                         symlinks out: skills, tools, profiles, kernels, images, AGENTS.md
inbox/<folder>/                collected material for one case (locked after case add)
cases/{refine,test}/<id>/      case.json, truth.json, src/, sol.md, fix.patch, poc/, kasan.log
vmimg/<img>/                   case KASAN kernels under opaque names (bzImage, vmlinux)
generations/gen-NN/skills/     copies of both skills per generation (gen-00 = baseline)
runs/control/<split>/<id>/r<k>/   control runs
runs/gen-NN/<split>/<id>/r<k>/    skill-group runs; diagnosis.json in runs/gen-NN/refine/<id>/
scores/{control,gen-NN}.<split>.json
lessons/gen-NN.md              failure lessons and edit plan
REPORT.md                      the session report (§9)
docs/failure-taxonomy.md       M and S codes, and the rules for turning cases into edits
```

## 1. Start: read the state

```bash
cd /workspace/SKILL-SIF && bin/sif status && bin/sif case ls
```

Continue from the first unfinished step below; never restart a loop that is
under way. If a detection phase is open (an interrupted session), wait for
or discard its subagents, then `bin/sif score <group> --split <split>`.

If `status` notes that a live skill differs from the gen-00 baseline, the
skills changed outside this loop. Archive the current loop
(`generations/`, `runs/`, `scores/`, `lessons/`, `state.json` into
`archive/loop-<date>/`), keep the cases, and start again with
`bin/sif gen init`. Record that in `REPORT.md`.

## 2. Collect cases (orchestrator only; network allowed)

### Choosing CVEs

- The fix commit, a root-cause description, and a PoC that produces a KASAN
  report must all be public.
- Prefer CVEs fixed after the model's knowledge cutoff (Opus 5.5: June
  2026); older ones are allowed but are more likely to be memorised.
- Spread weakness classes (UAF, OOB, race, refcount, integer) and
  subsystems. Past kernelCTF CVEs are good candidates: they come with
  write-ups and often with an official KASAN release that still contains
  the bug.
- The split is assigned at random by `case add` (`--split auto`); never move
  a case between splits.
- Stop collecting at `budget.max_cases`. With fewer than about 20 refine
  cases one case moves `combined` by several points; say so when reporting.

### Building one case

Put the material in `inbox/<folder>/` (the folder name is never shown to a
detector):

```text
inbox/<folder>/src/        vulnerable source: the full tree at the fix commit's first parent
                           (a stable or mainline snapshot tarball; no .git)
inbox/<folder>/sol.md      the root cause as you transcribed it, with path:line citations and one CWE id
inbox/<folder>/fix.patch   the upstream fix
inbox/<folder>/poc/poc.c   the public PoC, normalised to one C file (+ ldlibs.txt, run.json)
inbox/<folder>/kasan.log   the public KASAN report, if published
inbox/<folder>/config      the kernel config of the case kernel
```

Kernel for the case, in this order:

1. An existing official KASAN build under `links/kernels/` whose source
   still contains the bug (check the fix is absent in its commit).
2. An official kernelCTF KASAN release that contains the bug, downloaded
   over HTTPS into a new `kernels/sif-<release>/` (image and `vmlinux`
   only).
3. Otherwise build one: a new `kernels/sif-build-<id>/` holding the
   snapshot, a build profile `profiles/sif-build-<id>/profile.sh` (KSRC,
   KOBJ, FS=`$IMAGES/x64`), the target config merged with
   `configs/kasan_config`, then `tools/kernel.sh -p sif-build-<id>
   --olddefconfig` and `--build`. To hide the stable sublevel, set
   `SUBLEVEL = 0` and an empty `EXTRAVERSION` in the build copy's top
   `Makefile` and leave `CONFIG_LOCALVERSION` empty; then pass
   `--version-hidden`. Only builds within `budget.max_disk_gb`. After
   `case add` has imported the image, delete the build tree and the build
   profile.

Then:

```bash
bin/sif case add --from inbox/<folder> --kernel links/kernels/<dir> [--scope <dir> ...] [--cwe CWE-<n>] [--cve <id>]
bin/sif case verify <id>      # public PoC on fresh VMs; writes kasan.log and a draft truth.kasan
# complete cases/<split>/<id>/truth.json: functions, statements, kasan.functions
bin/sif case review <id>      # validates the truth against src/ and marks it reviewed
```

- `case add` stores only the subsystem in scope (default: the directories of
  the truth files), the headers it includes, and the config with version
  lines removed. It gives the case a random id, imports the kernel into
  `vmimg/` under an opaque name, and records the CVE and source path only in
  `case.json` (locked during detection).
- **Truth.** Transcribe the fix and the write-up into `truth.json`: the
  responsible function(s) and the narrow statement range(s) in the stored
  `src/`; for an add-only fix, the unchecked use rather than the insertion
  point. From the verified KASAN report, keep in `truth.kasan.functions` the
  function(s) that identify the root cause (the faulting access site and, if
  needed, its direct caller), not generic helpers. If the patch and the
  report do not determine one function and statement, drop the case.
- **Verification.** If the public PoC gives no KASAN report after the
  configured attempts, or the report is not at the patched code, drop the
  case: `bin/sif case drop <id> --reason "<why>"`. Do not adapt the PoC
  beyond normalising its build.
- After `case add`, delete `inbox/<folder>/src/` to save disk (the stored
  case keeps what it needs).

## Answer isolation

Detectors and controls must never see answers, other runs, or skills they
are not given. Enforced, not only requested:

- A run workspace holds the extracted source, `task.md`, and (skill group
  only) the generation's copies of both skills. Nothing else.
- `bin/sif dispatch detector|control` builds the workspaces and run
  profiles first, then makes `inbox/`, `cases/`, `generations/`,
  `lessons/`, `scores/`, `archive/`, and the live skill directories
  unreadable (mode 000) before any subagent starts. A control phase also
  locks the skill-group run directories. `bin/sif score` releases the locks
  and ends the phase; only one phase is open at a time.
- Each run has its own VM profile (`sif-<random>`, network-isolated) whose
  kernel path is opaque. The run's VM console logs are copied into the run
  directory at scoring, and the profile is removed.
- The lock is not a sandbox. `bin/sif score` scans each run's trajectory and
  written files for answer paths, other runs, skill files (control), and
  other VM profiles. A contaminated run scores as failed; re-dispatch it
  once with `--retry-contaminated` and score again. Record contamination in
  the lessons file.
- Never quote or paraphrase `sol.md`, `truth.json`, the fix, the public
  PoC, or its KASAN report in anything a detector or control can see:
  dispatch prompts, `task.md`, role files, and above all skill generations.

## Roles

| Role | Who | Stationed at | Reads | Writes |
|---|---|---|---|---|
| Orchestrator | You (session model) | `SKILL-SIF/` | everything | cases, `generations/`, `lessons/`, `REPORT.md`; live skills only via `promote --auto` |
| Control | one subagent per case × run | `runs/control/<split>/<case>/r<k>/` | its workspace and VM profile | `out/`, `agent/` there |
| Detector | one subagent per case × run | `runs/gen-NN/<split>/<case>/r<k>/` | its workspace (with `skills/`) and VM profile | `out/`, `agent/` there |
| Diagnoser | one subagent per failing case | `runs/gen-NN/refine/<case>/` | that case's runs, its `cases/` directory | `diagnosis.json` there |

- `bin/sif dispatch` prints one prompt per run. Send each **verbatim** with
  the Agent tool (`subagent_type: "general-purpose"`, the printed
  `description`, `model`, and `effort`). Add nothing: you have seen the
  answers, and anything you add can leak and makes runs incomparable.
- Send at most `budget.max_parallel_agents` Agent calls per message and
  wait for the whole phase before scoring. Read every hand-back: unfollowed
  skill steps are evidence for §5; VMs a subagent reports as still running
  are removed by `score`.
- A missing or malformed report scores as failed. Do not repair outputs,
  answer questions, or re-dispatch to get a better result. Re-dispatch
  (`--force --cases <id>`) only after an infrastructure failure, and record
  it.
- `bin/sif run <group>` (one `claude -p` per run, with a trajectory and
  enforced tool allow-list) is the alternative to Agent dispatch. Use one
  mode for the whole loop.
- Deciding what to change and editing the skills are yours. Do not delegate
  them.

## 3. Control group (once per case)

```bash
bin/sif dispatch control --split refine     # runs_per_case runs per case; locks; prints prompts
# send every prompt; wait for all
bin/sif score control --split refine        # unlocks, scores root cause and re-runs PoCs on fresh VMs
```

Run the control group right after the cases are reviewed and before the
first skill-group dispatch. It does not depend on the skills, so it is never
re-run per generation; for cases added later, dispatch it with
`--cases <id> ...` and score again. A case the control group solves in the
majority of runs is flagged `memorized_likely`.

## 4. Skill group: dispatch, collect, score

```bash
bin/sif gen init                         # first time only: gen-00 = copies of the live skills
bin/sif dispatch detector gen-NN         # runs_per_case runs per case; locks; prints prompts
# send every prompt; wait for all
bin/sif score gen-NN                     # unlocks; rc_rate, poc_rate, combined, effect vs control, +G/−L
bin/sif dispatch detector gen-NN --retry-contaminated   # only if score listed contaminated runs; then score again
```

- Scoring re-runs each run's final `out/poc/poc.c` on fresh isolated VMs
  (up to `poc.score_attempts`, infrastructure failures retried
  `poc.infra_retries` times, then `INFRA_BLOCKED`). Success needs a KASAN
  report whose function or top frames match `truth.kasan.functions`.
- Runs vary. A difference of one case between generations is noise unless
  it repeats.

## 5. Diagnose, then think

```bash
bin/sif dispatch diagnoser gen-NN        # one prompt per case that failed in the majority of runs
# send every prompt; wait for all
bin/sif diagnose gen-NN                  # writes lessons/gen-NN.md from every diagnosis.json
```

Then do the part that is yours, in `lessons/gen-NN.md`:

1. **Check the diagnoses.** For regressions (−L), low-confidence or
   surprising diagnoses, read the runs' worklogs, records, and console logs
   yourself.
2. **Handle `truth_issue` first.** If the truth is wrong (checked against
   `fix.patch` and `kasan.log`), correct `truth.json`, re-score every
   generation and the control group, and do not count it as a round.
3. **Only repeating failures count.** A failure seen in one run of three is
   noise. Weigh down `memorized_likely` cases: the control group solves
   them, so they say little about the skills.
4. **Group by cause, not by code.** Group the `general_gap` statements that
   one change would fix. Keep root-cause lessons (vuln-discovery) and
   reproducer lessons (dynamic-validation §3–§4) apart.
5. **Explain regressions** by the edit that caused them.
6. **Look across generations.** A lesson already applied whose cases still
   fail was not fixed by that edit; find out why instead of repeating it
   louder.
7. **Separate skill from harness.** If failures are mostly output or
   infrastructure (M7, M10, `INFRA_BLOCKED`), fix the harness (`task.md`
   template, role files, `config.json`) — which restarts the loop from
   gen-00 because settings changed — and record that.
8. **Write the lessons table and edit plan**: each lesson as general
   procedure, its supporting cases and run counts, and the one place (skill,
   file, section) where it goes. A lesson needs two or more supporting
   cases, or one case whose failure repeats plus a regression it explains.

Choose two or three edits per generation so the score change can be
attributed.

## 6. Apply it to the next generation

```bash
bin/sif gen new --note "<one line: which lessons>"
# edit generations/gen-NN/skills/vuln-discovery/ and/or the editable block of .../dynamic-validation/SKILL.md
bin/sif gen lint gen-NN
```

`gen new` copies the best-scoring generation, so a worse generation is rolled
back automatically; its lessons still count.

Rules for the edit:

- One targeted procedural change per lesson: what to read first, what to
  check, what counts as a covering guard, how to narrow to a statement, how
  to choose the class, how to build the state a reproducer needs, how to
  attribute a crash.
- Write procedure, not answers. Never put a case's CVE, file, function, KASAN
  location, or fix into a skill, and never describe a bug so specifically
  that it identifies one case. `gen lint` rejects the identifiers it can
  detect; the rule is broader than the lint.
- Prefer replacing or moving text to appending.
- Do not delete or weaken the parts of `vuln-discovery` that real audits need
  (configs, prior work, kernelCTF steps, model settings); make
  benchmark-heavy steps conditional on the task shape instead.
- `gen lint` fails if a `sif:protected` block changes or, for
  `dynamic-validation`, if anything outside its `sif:editable` block
  changes. Safety rules are out of bounds whatever the score.
- Explain each edit in `GEN.json` → `note` and in the lessons file's edit
  plan, so that lesson → edit → score can be audited.

Then dispatch the detectors on the new generation (§4) and compare +G/−L with
what each edit was expected to fix.

## 7. Stop and freeze

`bin/sif status` shows the stop rule: `max_rounds` generations after the
baseline, `patience` consecutive generations without a new best, or an
exhausted budget. When it reports a stop:

```bash
bin/sif freeze
bin/sif dispatch control --split test        && bin/sif score control --split test
bin/sif dispatch detector gen-00 --split test && bin/sif score gen-00 --split test
bin/sif dispatch detector <frozen> --split test && bin/sif score <frozen> --split test
```

(Send each phase's prompts and wait before its `score`.) The test split is
used once and never diagnosed.

## 8. Write-back (automatic, guarded)

```bash
bin/sif promote          # prints the diff and every unmet condition
bin/sif promote --auto   # writes back only when all conditions hold
```

`promote --auto` writes the frozen generation into the live skills only if
all of these hold; otherwise it records "반영 보류" with the reasons and
writes nothing:

- the frozen generation is not gen-00, passed lint, and its hash is the one
  that was scored;
- on the test split it beats gen-00 on `combined`, and neither `rc_rate` nor
  `poc_rate` falls; its effect over the control group does not shrink;
- the test split has at least `promote.min_test_cases` cases;
- the live skills have not changed since gen-00 was taken, and every
  `sif:protected` block (and, for dynamic-validation, everything outside the
  editable block) is identical to the live skills.

It backs the live skills up to `archive/pre-promote-<time>/` first and
prints the revert command (`bin/sif revert <backup>`). It never commits.
Lessons that concern other skills, `AGENTS.md`, or the harness go into
`REPORT.md` as suggestions only.

## 9. Report

End every session by writing `SKILL-SIF/REPORT.md` (replace it; it is the
one file a human reads) and summarising it in the conversation:

- the `bin/sif status` table and budget usage
- cases added, dropped (with reasons), and memorised-likely
- per generation: `combined`, `rc_rate`, `poc_rate`, effect over control,
  +G/−L, and the lessons behind each edit with their support
- the promotion decision and its reasons, the backup path, and the revert
  command
- decisions taken by default, `AWAITING_APPROVAL` items, infrastructure
  failures, and what is left to do

Report failed and regressed generations as they are. A loop that ends with
no improvement is a valid result.
