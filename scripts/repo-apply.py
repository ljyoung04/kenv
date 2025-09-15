#!/usr/bin/env python3
"""
Apply a monolithic `repo diff` output to an AOSP checkout.

This script splits the diff by `project <path>` markers and applies each
chunk inside the corresponding git sub-repository.

Features
- Dry run (validation only)
- Choose patch tool: git-apply (default) or GNU patch
- Continue-on-error mode
- Reverse apply (-R)

Usage
  ./apply-repo-diff.py -d path/to/repo.diff -r /path/to/aosp

Tip: You can also pipe the diff from stdin with -d -

Tested with Python 3.8+.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Dict, List, Tuple

PROJECT_RE = re.compile(r"^project\s+(.+?)\s*$")


def parse_repo_diff(lines: List[str]) -> List[Tuple[str, List[str]]]:
    """Parse a `repo diff` into [(project_path, patch_lines)].

    The header lines look like: `project frameworks/base/` (sometimes with
    trailing whitespace). We capture the project path token as-is, then trim
    any trailing colon-like decorations that some repo versions append.
    """
    groups: List[Tuple[str, List[str]]] = []
    current_proj: str = None
    current_buf: List[str] = []

    def push():
        nonlocal current_proj, current_buf
        if current_proj is not None and current_buf:
            groups.append((current_proj, current_buf))
        current_proj, current_buf = None, []

    for line in lines:
        m = PROJECT_RE.match(line)
        if m:
            # New project header encountered -> flush previous
            push()
            raw = m.group(1).strip()
            # Normalize path: drop any trailing annotations after a space or colon
            # e.g., "external/v8 : something" -> "external/v8"
            path = raw.split(" :", 1)[0].split("\t", 1)[0].strip()
            # Some outputs may show trailing slashes; keep but also tolerate when joining
            current_proj = path.rstrip("\n")
            continue
        # Accumulate patch lines for the current project
        current_buf.append(line)
    # Flush last
    push()
    return groups


def run(cmd: List[str], cwd: str) -> Tuple[int, str, str]:
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    return p.returncode, out, err


def apply_chunk(tool: str, proj_dir: str, patch_text: str, dry_run: bool, reverse: bool) -> Tuple[bool, str]:
    """Apply a single project patch chunk.

    Returns (success, log_text)
    """
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".patch") as tf:
        tf.write(patch_text)
        tmp_path = tf.name
    try:
        if tool == "git-apply":
            args = ["git", "apply", "--index", "--whitespace=nowarn"]
            if dry_run:
                args.append("--check")
            if reverse:
                args.append("-R")
            args.append(tmp_path)
            code, out, err = run(args, proj_dir)
        elif tool == "patch":
            # -p1 for git-style diffs (a/ b/ prefixes)
            args = ["patch", "-p1", "--follow-symlinks", "--backup", "--reject-file=-"]
            if reverse:
                args.append("-R")
            if dry_run:
                args.extend(["--dry-run"])  # patch prints what it would do
            args.extend(["-i", tmp_path])
            code, out, err = run(args, proj_dir)
        else:
            return False, f"Unsupported tool: {tool}"
        ok = (code == 0)
        return ok, (out + ("\n" if out and err else "") + err).strip()
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser(description="Apply a `repo diff` across an AOSP tree")
    ap.add_argument("-d", "--diff", required=True, help="Path to repo.diff (or '-' for stdin)")
    ap.add_argument("-r", "--root", required=True, help="Path to AOSP checkout root (where .repo/ lives)")
    ap.add_argument("--tool", choices=["git-apply", "patch"], default="git-apply", help="Apply tool to use")
    ap.add_argument("--continue-on-error", action="store_true", help="Do not stop on first failure")
    ap.add_argument("--dry-run", action="store_true", help="Validate without applying")
    ap.add_argument("-R", "--reverse", action="store_true", help="Reverse apply (unapply)")
    args = ap.parse_args()

    aosp_root = os.path.abspath(args.root)
    if not os.path.isdir(aosp_root) or not os.path.isdir(os.path.join(aosp_root, ".repo")):
        print(f"[error] '{aosp_root}' does not look like an AOSP repo root (.repo missing)", file=sys.stderr)
        sys.exit(2)

    # Load diff
    if args.diff == "-":
        diff_lines = sys.stdin.read().splitlines(True)
    else:
        with open(args.diff, "r", encoding="utf-8", errors="replace") as f:
            diff_lines = f.readlines()

    groups = parse_repo_diff(diff_lines)
    if not groups:
        print("[error] No 'project <path>' sections found in diff. Is this a `repo diff` output?", file=sys.stderr)
        sys.exit(2)

    print(f"[*] Found {len(groups)} project section(s) in diff")

    failures: List[Tuple[str, str]] = []
    for idx, (proj_path, patch_lines) in enumerate(groups, 1):
        # Normalize proj dir
        proj_dir = os.path.join(aosp_root, proj_path)
        # Some repo outputs include trailing slash; tolerate both
        if not os.path.isdir(proj_dir) and proj_path.endswith("/"):
            proj_dir = os.path.join(aosp_root, proj_path[:-1])
        print(f"[{idx}/{len(groups)}] Applying to project: {proj_path}")
        if not os.path.isdir(proj_dir):
            msg = f"Project directory does not exist: {proj_dir}"
            print(f"    [FAIL] {msg}")
            failures.append((proj_path, msg))
            if not args.continue_on_error:
                break
            else:
                continue

        # Sanity: ensure it's a git repo
        if not os.path.isdir(os.path.join(proj_dir, ".git")):
            msg = f"Not a git repository: {proj_dir}"
            print(f"    [FAIL] {msg}")
            failures.append((proj_path, msg))
            if not args.continue_on_error:
                break
            else:
                continue

        ok, log = apply_chunk(args.tool, proj_dir, ''.join(patch_lines), args.dry_run, args.reverse)
        if ok:
            mode = "DRY-RUN" if args.dry_run else "APPLIED"
            print(f"    [OK] {mode} via {args.tool}")
        else:
            print(f"    [FAIL] via {args.tool}\n------ LOG BEGIN ------\n{log}\n------- LOG END -------")
            failures.append((proj_path, log))
            if not args.continue_on_error:
                break

    if failures:
        print(f"\n[summary] {len(failures)} project(s) failed:")
        for proj, msg in failures:
            print(f"  - {proj}: {msg.splitlines()[0] if msg else 'unknown error'}")
        sys.exit(1)
    else:
        print("\n[summary] All project patches processed successfully.")


if __name__ == "__main__":
    main()
