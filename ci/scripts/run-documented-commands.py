#!/usr/bin/env python3
"""
run-documented-commands.py -- Execute a markdown file's own command blocks.

Documentation that tells a human to run commands rots unless something
executes those exact commands. This runner extracts fenced ```bash blocks
that are explicitly marked for verification and runs each one, in document
order, failing loudly on the first non-zero exit. The README *is* the test:
there is no second copy of the instructions that can drift.

Marking a block (the marker goes on its own line, directly above the fence;
an optional label after a colon names the block in output):

    <!-- ci-verify: boot the stack -->
    ```bash
    cd reference/local-dev
    docker compose up -d --wait
    ```

Unmarked blocks are ignored -- optional or destructive instructions stay
human-only.

Each block runs in its own bash process (bash -euxo pipefail) with the
repository root as the working directory, so every block must be
self-contained (start with `cd` if needed). Output is streamed unfiltered:
a failing documented command must never fail silently.

Usage:
  python ci/scripts/run-documented-commands.py <markdown-file> [--list]

  --list  print the marked blocks without executing them
"""
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

BLOCK_RE = re.compile(
    r"^<!-- ci-verify(?::[ \t]*(?P<label>[^>]*?))?[ \t]*-->[ \t]*\n"
    r"```bash[ \t]*\n"
    r"(?P<body>.*?)"
    r"^```[ \t]*$",
    re.MULTILINE | re.DOTALL,
)


def extract_blocks(md_path: Path):
    """Return [(label, command_text), ...] in document order."""
    text = md_path.read_text()
    blocks = []
    for m in BLOCK_RE.finditer(text):
        label = (m.group("label") or f"block {len(blocks) + 1}").strip()
        blocks.append((label, m.group("body")))
    return blocks


def main():
    args = [a for a in sys.argv[1:] if a != "--list"]
    list_only = "--list" in sys.argv[1:]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    md_path = Path(args[0])
    if not md_path.exists():
        print(f"ERROR: {md_path} not found", file=sys.stderr)
        sys.exit(2)

    blocks = extract_blocks(md_path)
    if not blocks:
        print(f"ERROR: no '<!-- ci-verify -->' blocks found in {md_path} -- "
              f"nothing verified is a failure, not a pass", file=sys.stderr)
        sys.exit(1)

    print(f"{md_path}: {len(blocks)} verified block(s)")
    for i, (label, body) in enumerate(blocks, 1):
        print(f"\n=== [{i}/{len(blocks)}] {label} ===")
        if list_only:
            print(body.rstrip())
            continue
        # -x echoes each command before running it, so failure output always
        # shows WHICH documented command failed.
        result = subprocess.run(
            ["bash", "-euxo", "pipefail", "-c", body], cwd=REPO_ROOT
        )
        if result.returncode != 0:
            print(f"\nFAIL: documented block [{i}] '{label}' exited "
                  f"{result.returncode} -- the instructions in {md_path} "
                  f"do not work as written.", file=sys.stderr)
            sys.exit(result.returncode)
        print(f"=== [{i}/{len(blocks)}] {label}: OK ===")

    if not list_only:
        print(f"\nPASS: all {len(blocks)} documented block(s) ran clean.")


if __name__ == "__main__":
    main()
