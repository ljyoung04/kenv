---
name: kctf-official-helper
description: Interact with the official kernelCTF service (info query, LTS vuln-trigger test) only when the user has authorized that exact action, target, and attempt count, and preserve reproducible evidence. Not for public-rules lookups, hardened-target attempts, or submission.
---

# kernelCTF Official Helper

Separate public information lookups from actions that touch the official
service or consume attempts. Record enough to reconstruct the exact target,
payload, and result. This skill does not grant authorization.

## Entry gate

1. Read root `AGENTS.md` and the skill for the active stage.
2. Read the current [rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md)
   and [server guide](https://google.github.io/security-research/kernelctf/server/).
   Record lookup time, URLs, targets, LTS, and limits.
3. Before connecting, confirm the user-approved **action**, destination,
   Candidate-ID, Target-ID, exact upload files, and maximum attempts in the
   current conversation. `tools/connect.sh`, the certificate, earlier
   approvals, or permission for local testing are not authorization.

Public web material (rules, release metadata, artifacts over HTTPS) needs no
approval. `info` still connects to the official service, so it needs
approval. Prefer public data when it is enough.

## Actions

| Action | Purpose | Limit |
|---|---|---|
| `info` | Active targets, configs, releases, artifact URLs | Information queries only |
| `vuln-test` | Run `--vuln-trigger` on the designated LTS / LTS-KASAN target | A crash is reproduction evidence; do not go on to other targets |
| `exit` | End the session | Use on unexpected prompts, targets, authentication, or upload scope |

Approval for one action does not cover another. Hardened-target attempts,
full evaluation, submission forms, and PRs are outside this skill.

## Execution

- Preferred entry point: `tools/kctf.sh` (documented in root `AGENTS.md`). It
  wraps the official client `user/.../kernelctf/server/client/cli.py` and
  refuses `lpe-test`/`vuln-test`/`evaluate` against the official server unless
  `KCTF_CONFIRM_OFFICIAL=1` is set. That gate is a backstop, NOT authorization:
  only set it after the user approves the exact action/target/attempts here.
  `tools/kctf.sh info` is the read-only query (still connects to the service).
- Read `tools/connect.sh` before use. It runs
  `socat - ssl:<host:port>,cafile=tools/server_cert.pem`, with default target
  `kernelctf.vrp.ctfcompetition.com:1337`. Use another target only if the
  user names it.
- The session is interactive. Read each server prompt and answer it. Do not
  pipe in pre-scripted answers based on guessed prompts.
- Before uploading, record the payload path, size, SHA-256, build command,
  and IDs. Keep tokens, session keys, and flags out of command lines, logs,
  and `FINDINGS.md`.
- For each run, record start and end time, action, the target and release
  the server reported, payload hash, result, duration, and remaining
  attempts in `agent/<research-name>/official/<run-id>/`, with a redacted
  transcript.
- When downloading artifacts listed by `info`, check that the URL matches the
  target and release. Store them under new, target-specific paths in
  `kernels/`, and record their SHA-256.

Stop when the approved attempts are used up, a definite result is in, the
target, prompts, or authentication differ from what was expected, or
infrastructure errors block valid runs. Report back and get fresh approval
for any new action, extra attempt, or submission.
