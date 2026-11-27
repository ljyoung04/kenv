# Failure taxonomy (local)

The reference paper (arXiv:2610.25705v1) codes failed trajectories into seven
agent-execution mechanisms (M1–M7) and seven skill-level limitations (S1–S7).
The codes below are this workspace's own (M8–M10 and S8–S9 cover the KASAN
reproducer part, which the paper does not have). Refine them as lessons accumulate; do not present them as the
paper's.

Give every failed case one M code (what the run did) and one S code (what in
the skill text allowed it). An S code is what an edit can fix. If the answer is
"the skill said the right thing and the run ignored it", the edit is about
placement, emphasis, or a gate — not more text.

## M — what the run did

| Code | Mechanism | Typical evidence in the trajectory |
|---|---|---|
| M1 | Never read the responsible code | Target function absent from Read/Grep calls |
| M2 | Read it, formed no hypothesis there | Function read; no candidate or rejection mentions it |
| M3 | Right hypothesis, wrongly falsified | Candidate record `REJECTED` citing a guard that does not cover the path |
| M4 | Right area, wrong location reported | Reports caller/callee or symptom site instead of the responsible statement |
| M5 | Right location, wrong weakness class | Function/statement match, CWE mismatch |
| M6 | Budget spent on procedure | Scope/eligibility/map bookkeeping dominates; analysis truncated or timed out |
| M7 | Output failure | No report, malformed JSON, range too wide, ranked below top-k |
| M8 | Reproducer never reached the defect | PoC compiles and runs, but `poc-runs.md`/console show it stopped at setup, permission, or wrong entry path |
| M9 | Reproducer hit a different bug or none in time | KASAN report at a different function/object, or races never won within the budget |
| M10 | Reproducer output failure | No `poc.c`, compile failure, VM budget exhausted on infrastructure |

## S — what the skill allowed

| Code | Limitation | Usual edit |
|---|---|---|
| S1 | Coverage: bug class or code pattern not in the procedure | Add the missing check to the relevant pass |
| S2 | Prioritisation: procedure leads attention away from the defect | Reorder steps or change the selection rule |
| S3 | Falsification too eager or too weak | Tighten what counts as a covering guard |
| S4 | Localisation: no instruction to narrow to the responsible statement | Add a localisation step before reporting |
| S5 | Classification: no rule mapping mechanism to weakness class | Add or correct a mechanism → CWE rule |
| S6 | Overhead: steps that do not fit a file-guided task | Make the step conditional; do not delete what real audits need |
| S7 | Ambiguity or conflict between instructions | Rewrite; remove the conflicting text |
| S8 | Reproducer procedure gap: no step to build the state, privilege, or timing the root cause needs | Add the step to dynamic-validation §3–§4 (its only editable part) |
| S9 | Causality check missing: the procedure lets a run accept or chase a crash that is not the reported root cause | Tighten the §4 attribution step |

## From cases to an edit

1. Each case runs several times per generation. Only a failure that repeats
   in the majority of a case's runs counts for that case. A lesson needs at
   least two supporting cases, or one case plus a regression it explains.
   Single-case lessons are recorded, not applied.
2. Weigh down cases the control group (no skill) also solves: the model may
   know them from training, so they say little about the skill.
3. One targeted edit per lesson. Prefer replacing or moving text to appending;
   a skill that only grows gets slower and more self-contradictory (M6, S7).
4. An S6 edit must not weaken the skill for its real use (audits under
   `agent/`). Make benchmark-specific overhead conditional on the task shape.
5. Write what the analyst should *do*, never what the answer *was*.
