---
name: kctf-official-helper
description: Safely query official KernelCTF service information, obtain artifacts, run LTS triggers and hardened exploit tests, and preserve evidence when the user has authorized the exact action and destination. Do not use for public-rules-only lookups or unauthorized remote evaluation or submission.
---

# KernelCTF Official Helper

Distinguish public information queries from executions that consume attempts when interacting with official KernelCTF remote services. Preserve enough information to reconstruct the exact target, payload, and result. This skill does not grant remote-use authorization.

## Entry Gate

1. First read root `AGENTS.md` and the skill for the active stage.
2. Check the current [official KernelCTF rules](https://github.com/google/security-research/blob/master/kernelctf/rules.md) and [official service guide](https://google.github.io/security-research/kernelctf/server/). Record lookup times, URLs, active targets/LTS, and execution limits.
3. Before connecting remotely, verify the user-authorized `action`, destination, Candidate-ID, Target-ID, exact files to upload, and maximum attempts. Do not infer remote authorization from the existence of `connect.sh` or certificates, approval of a different action, or permission for local testing.

Reading public rules, source, release metadata, and artifacts on the web falls within root `AGENTS.md`'s read-only scope. However, even `info` connects to the official evaluation service and requires explicit approval. Prefer public information over remote `info` when it suffices.

## Actions

| Action | Purpose | Additional caution |
|---|---|---|
| `info` | Check active targets, configurations, kernel releases, and public artifact URLs | Do not proceed to menus beyond information queries. |
| `vuln-test` | Check the `--vuln-trigger` path on designated LTS/LTS-KASAN | A kernel crash is reproduction evidence, not exploit success. |
| `lpe-test` | Test the flag acquisition path on the hardened target | Record exact starting privileges and target mitigations. |
| `evaluate` | Full evaluation under the official contract | Consumes limited evaluation attempts; requires authorization specifying this action and attempt count. |
| `exit` | End interaction | Exit on unexpected prompts, targets, authentication requirements, or upload scope. |

`lpe-test`, `vuln-test`, and `evaluate` are separate remote executions. Do not extend authorization for one action to the others. Submission forms, flag submissions, PRs, and external reports are not included in authorization for any action.

## Execution and Evidence Preservation

- Read the current `/workspace/tools/connect.sh` and CA certificate path; verify that the default destination is `kernelctf.vrp.ctfcompetition.com:1337`. Pass a different destination only when explicitly specified by the user.
- Connect interactively in a PTY using `tools/connect.sh [host:port]`. Do not send unattended input based on guessed prompts; check actions and targets displayed by the current server.
- Before uploading, record payload path, size, SHA-256, build command, and Candidate-ID/Target-ID. Do not expose authentication tokens, session keys, or flags in command lines, shared logs, or `FINDINGS.md`.
- Preserve each attempt's start/end time, action, exact server-reported target/release, payload hash, result, duration, and remaining attempt budget in `agent/<research-name>/official/<run-id>/`. Keep a transcript excluding sensitive original content, and hashes.
- Before downloading public HTTPS artifacts supplied by `info`, cross-check the target/release against the URL. Preserve kernel source, `bzImage`, `vmlinux`, and configuration under non-overwriting target-specific paths in `kernels/`, following root rules, and include SHA-256 in handoff records.

Stop when authorized attempts are exhausted, an exact result is obtained, the target/prompts/authentication requirements differ from expectations, or infrastructure errors prevent further valid experiments. If a new action, additional attempts, or submission is needed, report current results and new side effects and obtain authorization again.

