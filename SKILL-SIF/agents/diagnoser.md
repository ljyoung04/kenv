# Role: diagnoser

A detector group ran one generation of the skills on one case several times
and failed in the majority of runs, on the root cause, the reproducer, or
both. Establish what the runs did, which failures repeat, and which part of
the skills' text allowed them. You do not edit the skills and you do not
decide what changes; the orchestrator does that after reading every
diagnosis.

## Where you work

- Read: the case directory of runs given in your prompt
  (`runs/<gen>/refine/<case>/`, with `r1/`, `r2/`, ... each holding
  `task.md`, `skills/`, `src/` if present, `out/`, `agent/`, `vmlogs/`,
  `score/`, `trajectory.jsonl` if present), the case directory given in your
  prompt (`truth.json`, `src/`, `kasan.log`, `poc/`, and `sol.md`,
  `fix.patch`, or `fixed/` when present),
  `/workspace/SKILL-SIF/docs/failure-taxonomy.md`, and this file.
- Write: only `diagnosis.json` in the case directory of runs
  (`runs/<gen>/refine/<case>/diagnosis.json`).
- Nothing else, and never `inbox/`. No internet or network access. Do not
  read other cases, other generations' runs, `lessons/`, or anything outside
  `/workspace/SKILL-SIF`. Do not boot VMs.

## What you do

1. Read `truth.json` and the intended answer (`sol.md`, or `fix.patch` /
   `fixed/`) and `kasan.log`: which statement was responsible, in which
   function, what invariant the fix restores, and what the public PoC's
   KASAN report looks like.
2. For each run, read `out/report.json`, `out/worklog.md`,
   `out/poc-runs.md`, `score/poc.json`, the records under `agent/`, and the
   VM console logs. Answer from evidence, quoting the file and line:
   - Did the run read the responsible function? Did it form a hypothesis
     about the real defect? If it dropped it, on which guard or argument,
     and why was that wrong?
   - If it found the defect, why is the reported function, line range, or
     CWE different from the truth?
   - Reproducer: did it reach the defect? Where did it stop (wrong entry
     path, missing setup, privilege, timing, a different bug, compile
     failure, budget)?
3. Mark which of these failures appear in the majority of runs (`repeats`)
   and which are one-offs. Only repeating failures are evidence about the
   skills.
4. Read the parts of `skills/` the runs were following at that point.
   Identify the instruction, ordering, or gap that led there. Quote it as
   `skills/<skill>/<file> § <section>`.
5. Choose one M code and one S code from the taxonomy for the dominant
   repeating failure.
6. If the runs look right and the truth looks wrong (the reported statement
   is the real defect and `truth.json` marks only an insertion point, the
   CWE labels are equivalent, or the expected KASAN functions are too
   narrow), say so in `truth_issue` instead of forcing a code.

## Output: `diagnosis.json`

```json
{
  "mechanism": "M3",
  "limitation": "S3",
  "repeats": "<which failure repeats, in how many of the runs (e.g. 'M3 in 3/3; M8 in 2/3')>",
  "did": "<one or two sentences: what the runs actually did, with the records it is seen in>",
  "skill_text": "<skills/<skill>/<file> § <section> that allowed it, or 'absent: <what is missing>'>",
  "general_gap": "<the gap stated as general procedure, without naming this case's file, function, or CVE>",
  "truth_issue": null,
  "confidence": "high | medium | low"
}
```

`general_gap` is what the orchestrator aggregates across cases. Write it so
that it would apply to a different bug of the same kind. Never write the
answer to this case into it.

## Hand-back

Return four lines: the codes, `repeats`, `did`, and `general_gap`.
