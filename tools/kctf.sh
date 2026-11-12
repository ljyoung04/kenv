#!/usr/bin/env bash
# kctf.sh - thin, safe wrapper around the official kernelCTF tooling that lives
# (user-owned, unmodified) under user/kctf/security-research/kernelctf/.
#
# Paths are derived from this script's own location (like the other tools/*.sh);
# no env.sh sourcing, no inherited PRJ. Override the checkout location with
# KCTF_DIR=... if you keep it elsewhere.
#
# SAFETY MODEL (matches AGENTS.md "Safety and legacy paths" + the
# kctf-official-helper skill):
#   * Local / offline helpers run freely: check-config, check-submission,
#     repro-summary, sim (local VM), verify (local build), docs, paths.
#   * Actions that CONTACT THE OFFICIAL kernelCTF SERVER and run an exploit
#     (lpe-test / vuln-test / evaluate against --remote) are CONSEQUENTIAL and
#     externally visible. They are REFUSED unless the operator explicitly opts
#     in with KCTF_CONFIRM_OFFICIAL=1 (or the --i-understand-official token).
#     `--local` targets a local server/VM and is NOT gated.
#   * `info` is a read-only remote query; allowed, but it prints a notice.
#
# An agent must still obtain the user's explicit, per-attempt approval before
# setting KCTF_CONFIRM_OFFICIAL=1 -- the gate is a backstop, not a substitute
# for that approval.

set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PRJ="$(dirname "$SCRIPT_DIR")"
KCTF_DIR="${KCTF_DIR:-$PRJ/user/kctf/security-research/kernelctf}"
CLI="$KCTF_DIR/server/client/cli.py"
SIM="$KCTF_DIR/simulator/local_runner.sh"

RED=$'\033[91m'; YEL=$'\033[93m'; GRN=$'\033[92m'; GRY=$'\033[90m'; RST=$'\033[0m'
err()  { echo "${RED}[kctf] $*${RST}" >&2; }
warn() { echo "${YEL}[kctf] $*${RST}" >&2; }
info() { echo "${GRY}[kctf] $*${RST}" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1 ${2:-}"; exit 2; }; }
have_kctf() { [[ -f "$CLI" ]] || { err "kernelCTF client not found at: $CLI"; err "Set KCTF_DIR to the security-research/kernelctf checkout."; exit 2; }; }

# Returns 0 if any arg is literally --local
args_have_local() { for a in "$@"; do [[ "$a" == "--local" ]] && return 0; done; return 1; }

official_gate() {
    # $1 = action name; remaining args = the invocation args (to scan for opt-in)
    local action="$1"; shift
    if [[ "${KCTF_CONFIRM_OFFICIAL:-}" == "1" ]]; then return 0; fi
    for a in "$@"; do [[ "$a" == "--i-understand-official" ]] && return 0; done
    err "REFUSED: '$action' against the OFFICIAL kernelCTF server is a"
    err "consequential, externally visible action (runs your exploit on Google's"
    err "infrastructure and counts against quota for 'evaluate')."
    err ""
    err "To proceed, EITHER:"
    err "  - add --local   (targets a local server/VM, not the official service), or"
    err "  - re-run with   KCTF_CONFIRM_OFFICIAL=1 tools/kctf.sh $action ..."
    err "    (an agent must get the user's explicit approval first -- AGENTS.md)."
    exit 3
}

# Strip our own opt-in token before handing args to the real CLI.
strip_token() { local out=(); for a in "$@"; do [[ "$a" == "--i-understand-official" ]] || out+=("$a"); done; printf '%s\n' "${out[@]}"; }

usage() {
cat <<EOF
Usage: tools/kctf.sh <command> [args...]

Evaluation client (user/.../kernelctf/server/client/cli.py):
  info [--remote H:P] [-k]            Read-only: query active targets + artifact URLs
  lpe-test  <exploit> [cli args...]   Run exploit on the HARDENED target, check /flag read
  vuln-test <exploit> [cli args...]   Run 'exploit --vuln-trigger' on LTS, check crash/KASAN
  evaluate  <exploit> --researcher-token T [args...]
                                      Full official run (vuln x3 + 20 reliability runs + flag)
     * lpe-test/vuln-test/evaluate hit the OFFICIAL server unless you pass --local;
       official runs are gated behind KCTF_CONFIRM_OFFICIAL=1 (see safety note).
     * extra cli.py flags pass through: --local --root --insecure/-k
       --ignore-open-slots --wait-for-slot --no-official-run --save-flag[=FILE]
       --show-vm-output/--no-show-vm-output --server-path PATH

Local VM / offline helpers (no official server, run freely):
  sim <release-name> [--root]        Boot a release locally (simulator/local_runner.sh)
  check-config <target.config> [required.config]
                                      check_required_config.py: required kernelCTF options
  check-submission [mergeInto]       check-submission.py: validate a submission (git-based)
  repro-summary <repro.log>          repro_summary.py: summarize a repro log
  verify <exploit_path...> [flags]   vuln-verify/verify.py: build+verify on upstream/stable
  rules | style | faq                Print the local rules.md / style_guide.md / faq.md
  paths                              Print resolved paths + dependency check

Env:
  KCTF_DIR=<path>            Override the kernelctf checkout location
  KCTF_CONFIRM_OFFICIAL=1    Authorize official-server exploit runs (explicit opt-in)
EOF
}

cmd="${1:-help}"; shift || true

case "$cmd" in
  info)
    have_kctf; need socat
    info "Read-only query to the kernelCTF server (official unless --remote/--local given)."
    exec python3 "$CLI" --action info "$@"
    ;;

  lpe-test|vuln-test)
    have_kctf
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh $cmd <exploit> [cli args...]"; exit 1; }
    if args_have_local "$@"; then
        need qemu-system-x86_64; [[ -e /dev/kvm ]] || warn "/dev/kvm not present; local VM may fail"
    else
        need socat
        official_gate "$cmd" "$@"
    fi
    mapfile -t PASS < <(strip_token "$@")
    exploit="${PASS[0]}"; rest=("${PASS[@]:1}")
    exec python3 "$CLI" "$exploit" --action "$cmd" "${rest[@]}"
    ;;

  evaluate)
    have_kctf
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh evaluate <exploit> --researcher-token T [args...]"; exit 1; }
    if args_have_local "$@"; then
        need qemu-system-x86_64; [[ -e /dev/kvm ]] || warn "/dev/kvm not present; local VM may fail"
    else
        need socat
        official_gate "evaluate" "$@"
    fi
    mapfile -t PASS < <(strip_token "$@")
    exploit="${PASS[0]}"; rest=("${PASS[@]:1}")
    exec python3 "$CLI" "$exploit" --action evaluate "${rest[@]}"
    ;;

  sim)
    [[ -f "$SIM" ]] || { err "simulator not found at $SIM"; exit 2; }
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh sim <release-name> [--root]"; exit 1; }
    need qemu-system-x86_64; need wget; [[ -e /dev/kvm ]] || warn "/dev/kvm not present; VM may be slow/fail"
    info "Local VM only (no official server). Downloads artifacts into $KCTF_DIR/simulator/."
    ( cd "$KCTF_DIR/simulator" && exec bash "$SIM" "$@" )
    ;;

  check-config)
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh check-config <target.config> [required.config]"; exit 1; }
    exec python3 "$KCTF_DIR/check_required_config.py" "$@"
    ;;

  check-submission)
    exec python3 "$KCTF_DIR/check-submission.py" "$@"
    ;;

  repro-summary)
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh repro-summary <repro.log>"; exit 1; }
    exec python3 "$KCTF_DIR/repro_summary.py" "$@"
    ;;

  verify)
    [[ $# -ge 1 ]] || { err "usage: tools/kctf.sh verify <exploit_path...> [verify.py flags]"; exit 1; }
    [[ -f "$KCTF_DIR/vuln-verify/verify.py" ]] || { err "verify.py not found"; exit 2; }
    info "Local build+verify (needs image_runner, toolchains; may use network/gh auth)."
    exec python3 "$KCTF_DIR/vuln-verify/verify.py" "$@"
    ;;

  rules)  exec sed -n '1,9999p' "$KCTF_DIR/rules.md" ;;
  style)  exec sed -n '1,9999p' "$KCTF_DIR/style_guide.md" ;;
  faq)    exec sed -n '1,9999p' "$KCTF_DIR/faq.md" ;;

  paths)
    echo "KCTF_DIR : $KCTF_DIR    $( [[ -d "$KCTF_DIR" ]] && echo OK || echo MISSING )"
    echo "cli.py   : $CLI    $( [[ -f "$CLI" ]] && echo OK || echo MISSING )"
    echo "simulator: $SIM    $( [[ -f "$SIM" ]] && echo OK || echo MISSING )"
    echo "default remote: kernelctf.vrp.ctfcompetition.com:1337"
    echo -n "deps: "
    for d in python3 socat qemu-system-x86_64 wget; do
        command -v "$d" >/dev/null 2>&1 && echo -n "${GRN}$d${RST} " || echo -n "${RED}$d(missing)${RST} "
    done; echo
    echo -n "/dev/kvm: "; [[ -e /dev/kvm ]] && echo "${GRN}present${RST}" || echo "${RED}absent${RST}"
    echo "official gate: KCTF_CONFIRM_OFFICIAL=${KCTF_CONFIRM_OFFICIAL:-<unset -> official exploit runs REFUSED>}"
    ;;

  help|-h|--help) usage ;;
  *) err "unknown command: $cmd"; echo; usage; exit 1 ;;
esac
