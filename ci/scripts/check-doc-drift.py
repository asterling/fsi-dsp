#!/usr/bin/env python3
"""
check-doc-drift.py -- Detect drift between MANIFEST.yaml, on-disk assets,
and documentation count claims.

MANIFEST.yaml is the machine-readable capability contract consumed by
cflt-ai (fsi-dsp:// URI resolution). For agents and humans alike to trust
it as ground truth, three invariants must hold:

  1. Every capability path registered in MANIFEST.yaml exists on disk.
  2. Every on-disk asset of a registered type (scenario, ansible role,
     terraform module, ADR, accelerator layer) is registered in
     MANIFEST.yaml -- no stray assets.
  3. Documentation count claims (README.md, EXECSUMMARY.md) match the
     counts derived from MANIFEST.yaml / repo state -- no stale prose.

Usage: python ci/scripts/check-doc-drift.py [--enforce] [--allow-strays] [--fix]

  Default (report mode): print every finding, always exit 0. This lets
  the gate land and surface existing drift without turning CI red before
  the drift itself is fixed.

  --enforce: invariant 1, 2, and 3 findings exit 1 (CI-blocking). Stray
  assets (invariant 2) now block under --enforce so unregistered assets
  cannot land silently.

  --allow-strays: TEMPORARY rollout flag. Under --enforce, downgrades
  stray findings back to warning-only (exit 0 on strays alone), matching
  the pre-enforcement behavior. It exists solely so --enforce can be
  turned on in CI while a handful of known strays (1 ADR + 2 accelerator
  layers) are still awaiting their dedicated stray-registration PR --
  registering a stray is a manifest change, and apply_sequence layers
  additionally require a coordinated MODULE_TO_CANON_KEY update in
  cflt-ai's check-canon-parity.py. Once that PR lands and registers the
  remaining strays, this flag (and its use in the workflow) must be
  removed so strays block unconditionally. Has no effect without
  --enforce (report mode already treats strays as warnings).

  --fix: rewrite drifted doc counts in place from the derived counts
  (preserving digit vs number-word style) and append manifest-registered
  roles missing from the README role table, then re-check. Counts in
  docs are tool-generated, never hand-edited. Strays and missing
  manifest paths are never auto-fixed (they need manifest/repo changes).
"""
import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST = REPO_ROOT / "MANIFEST.yaml"

# Number words that appear in prose count claims
NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
    "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
    "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20,
}


NUMBER_WORDS_INV = {v: k for k, v in NUMBER_WORDS.items()}


def format_count(original_token: str, count: int) -> str:
    """Render count in the same style as the token it replaces."""
    if original_token.isdigit():
        return str(count)
    word = NUMBER_WORDS_INV.get(count)
    if word is None:
        return str(count)
    return word.capitalize() if original_token[0].isupper() else word


def parse_count(token: str) -> int:
    """Parse a digit or number-word token into an int."""
    token = token.lower()
    if token.isdigit():
        return int(token)
    if token in NUMBER_WORDS:
        return NUMBER_WORDS[token]
    raise ValueError(f"Unparseable count token: {token!r}")


def load_manifest() -> dict:
    with open(MANIFEST) as f:
        return yaml.safe_load(f)


def manifest_counts(manifest: dict) -> dict:
    """Derive per-type counts from MANIFEST.yaml capabilities, plus
    repo-state counts that docs also make claims about."""
    counts = {}
    for cap in manifest["capabilities"]:
        counts[cap["type"]] = counts.get(cap["type"], 0) + 1
        # Accelerator layers are apply_sequence sub-assets; docs claim their
        # total (e.g. "layers five Kustomize Components").
        counts["accelerator-layer"] = counts.get("accelerator-layer", 0) + len(
            cap.get("apply_sequence", [])
        )
    # Orchestration plays in the Ansible entrypoint ("N-play pipeline" claims)
    site_yml = REPO_ROOT / "ansible" / "site.yml"
    if site_yml.exists():
        plays = yaml.safe_load(site_yml.read_text())
        counts["site-play"] = len(plays) if isinstance(plays, list) else 0
    return counts


def check_manifest_paths(manifest: dict, failures: list):
    """Invariant 1: every registered path exists on disk."""
    for cap in manifest["capabilities"]:
        path = REPO_ROOT / cap["path"]
        if not path.exists():
            failures.append(
                f"MANIFEST path missing on disk: {cap['id']} -> {cap['path']}"
            )
        # apply_sequence layers are sub-assets with their own paths
        for layer in cap.get("apply_sequence", []):
            layer_path = REPO_ROOT / layer["path"]
            if not layer_path.exists():
                failures.append(
                    f"MANIFEST apply_sequence layer missing on disk: "
                    f"{cap['id']} -> {layer['path']}"
                )


def check_stray_assets(manifest: dict, warnings: list):
    """Invariant 2 (warning only): on-disk assets missing from the manifest."""
    registered_paths = {cap["path"] for cap in manifest["capabilities"]}

    # Scenario directories
    for d in sorted((REPO_ROOT / "scenarios").iterdir()):
        if d.is_dir() and f"scenarios/{d.name}" not in registered_paths:
            warnings.append(f"Stray scenario not in MANIFEST: scenarios/{d.name}")

    # Ansible roles
    for d in sorted((REPO_ROOT / "ansible" / "roles").iterdir()):
        if d.is_dir() and f"ansible/roles/{d.name}" not in registered_paths:
            warnings.append(f"Stray ansible role not in MANIFEST: ansible/roles/{d.name}")

    # Terraform modules
    for d in sorted((REPO_ROOT / "modules").iterdir()):
        if d.is_dir() and f"modules/{d.name}" not in registered_paths:
            warnings.append(f"Stray terraform module not in MANIFEST: modules/{d.name}")

    # ADRs (numbered files; 000-template.md is scaffolding, not an ADR)
    for f in sorted((REPO_ROOT / "docs" / "adr").glob("[0-9]*.md")):
        if f.name.startswith("000-"):
            continue
        if f"docs/adr/{f.name}" not in registered_paths:
            warnings.append(f"Stray ADR not in MANIFEST: docs/adr/{f.name}")

    # Accelerator layers must appear in their accelerator's apply_sequence
    for cap in manifest["capabilities"]:
        if cap["type"] != "accelerator":
            continue
        seq_paths = {layer["path"] for layer in cap.get("apply_sequence", [])}
        layers_dir = REPO_ROOT / cap["path"] / "layers"
        if not layers_dir.is_dir():
            continue
        for d in sorted(layers_dir.iterdir()):
            rel = f"{cap['path']}/layers/{d.name}"
            if d.is_dir() and rel not in seq_paths:
                warnings.append(
                    f"Stray accelerator layer not in {cap['id']} apply_sequence: {rel}"
                )


# Documentation count claims. Each entry: (file, pattern with one capture
# group, manifest type whose count the claim must match). If a pattern stops
# matching (doc reworded), that is also a failure -- update the pattern here
# in the same PR that rewords the doc.
DOC_CLAIMS = [
    ("EXECSUMMARY.md", r"across (\w+) deployment models", "scenario"),
    ("EXECSUMMARY.md", r"All (\w+) share identical governance", "scenario"),
    ("EXECSUMMARY.md", r"(\d+) deployment scenarios", "scenario"),
    ("EXECSUMMARY.md", r"(\d+) Ansible roles", "ansible-role"),
    ("EXECSUMMARY.md", r"(\w+)-play orchestration", "site-play"),
    ("EXECSUMMARY.md", r"(\d+) ADRs", "adr"),
    ("README.md", r"(\w+) roles providing full lifecycle", "ansible-role"),
    ("README.md", r"layers (\w+) Kustomize Components", "accelerator-layer"),
]


def check_doc_claims(manifest: dict, failures: list):
    """Invariant 3: doc count claims match manifest-derived counts."""
    counts = manifest_counts(manifest)
    for filename, pattern, cap_type in DOC_CLAIMS:
        text = (REPO_ROOT / filename).read_text()
        m = re.search(pattern, text)
        if not m:
            failures.append(
                f"{filename}: claim pattern not found (doc reworded?): {pattern!r}"
            )
            continue
        try:
            claimed = parse_count(m.group(1))
        except ValueError:
            failures.append(
                f"{filename}: unparseable count {m.group(1)!r} for {pattern!r}"
            )
            continue
        actual = counts.get(cap_type, 0)
        if claimed != actual:
            failures.append(
                f"{filename}: claims {claimed} {cap_type}(s), "
                f"MANIFEST has {actual} ({pattern!r})"
            )


def check_readme_role_table(manifest: dict, failures: list):
    """README's Ansible role table must list exactly the registered roles."""
    manifest_roles = {
        cap["name"] for cap in manifest["capabilities"]
        if cap["type"] == "ansible-role"
    }
    text = (REPO_ROOT / "README.md").read_text()
    table_roles = set(re.findall(r"^\| `(\w+)` \|", text, flags=re.MULTILINE))
    for missing in sorted(manifest_roles - table_roles):
        failures.append(f"README.md role table missing registered role: {missing}")
    for stray in sorted(table_roles - manifest_roles):
        failures.append(f"README.md role table lists unregistered role: {stray}")


def fix_doc_claims(manifest: dict) -> list:
    """--fix: rewrite drifted counts in place, same style as the original.
    Returns a list of 'file: old -> new' descriptions of applied fixes."""
    applied = []
    counts = manifest_counts(manifest)
    for filename, pattern, cap_type in DOC_CLAIMS:
        path = REPO_ROOT / filename
        text = path.read_text()
        m = re.search(pattern, text)
        if not m:
            continue  # pattern-not-found stays a finding; nothing to rewrite
        try:
            claimed = parse_count(m.group(1))
        except ValueError:
            continue
        actual = counts.get(cap_type, 0)
        if claimed == actual:
            continue
        replacement = format_count(m.group(1), actual)
        text = text[: m.start(1)] + replacement + text[m.end(1):]
        path.write_text(text)
        applied.append(f"{filename}: {m.group(1)!r} -> {replacement!r} ({cap_type})")
    return applied


def fix_readme_role_table(manifest: dict) -> list:
    """--fix: append manifest-registered roles missing from the README role
    table, using the manifest description. Never removes rows."""
    applied = []
    roles = {
        cap["name"]: cap.get("description", "")
        for cap in manifest["capabilities"] if cap["type"] == "ansible-role"
    }
    path = REPO_ROOT / "README.md"
    lines = path.read_text().splitlines(keepends=True)
    row_idx = [i for i, l in enumerate(lines) if re.match(r"^\| `(\w+)` \|", l)]
    if not row_idx:
        return applied
    present = {re.match(r"^\| `(\w+)` \|", lines[i]).group(1) for i in row_idx}
    insert_at = row_idx[-1] + 1
    new_rows = [
        f"| `{name}` | {roles[name]} |\n"
        for name in roles if name not in present
    ]
    if new_rows:
        lines[insert_at:insert_at] = new_rows
        path.write_text("".join(lines))
        applied.extend(f"README.md: added role table row for `{r.split('`')[1]}`"
                       for r in new_rows)
    return applied


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument(
        "--enforce", action="store_true",
        help="exit 1 on path/doc-claim/stray drift (default: report only, exit 0)",
    )
    parser.add_argument(
        "--allow-strays", action="store_true",
        help="TEMPORARY: under --enforce, keep strays warning-only (exit 0). "
             "Remove once the stray-registration PR lands.",
    )
    parser.add_argument(
        "--fix", action="store_true",
        help="rewrite drifted doc counts/table rows from derived counts, then re-check",
    )
    args = parser.parse_args()

    if not MANIFEST.exists():
        print("ERROR: MANIFEST.yaml not found", file=sys.stderr)
        sys.exit(1)

    manifest = load_manifest()

    if args.fix:
        applied = fix_doc_claims(manifest) + fix_readme_role_table(manifest)
        for a in applied:
            print(f"  FIXED: {a}")
        print(f"--fix applied {len(applied)} change(s); re-checking.\n")

    failures = []
    warnings = []

    check_manifest_paths(manifest, failures)
    check_stray_assets(manifest, warnings)
    check_doc_claims(manifest, failures)
    check_readme_role_table(manifest, failures)

    counts = manifest_counts(manifest)
    mode = "enforce" if args.enforce else "report"
    print(f"Doc-drift check ({mode} mode): MANIFEST v{manifest.get('version', '?')} -- "
          + ", ".join(f"{n} {t}" for t, n in sorted(counts.items())))

    # Strays block under --enforce unless the temporary --allow-strays flag
    # downgrades them to warning-only.
    strays_block = args.enforce and not args.allow_strays

    if warnings:
        if strays_block:
            note = "blocking under --enforce; register them or pass --allow-strays"
        else:
            note = "warning-only; register them in a dedicated manifest PR"
        print(f"\n{len(warnings)} stray asset(s) on disk but not in MANIFEST "
              f"({note}):")
        for w in warnings:
            print(f"  WARN: {w}")

    if failures:
        print(f"\n{len(failures)} drift issue(s) found:")
        for f in failures:
            print(f"  DRIFT: {f}")
    else:
        print("PASS: MANIFEST paths and doc count claims are in sync.")

    # A finding blocks CI only under --enforce. Doc-claim/path failures always
    # block; strays block too unless --allow-strays keeps them warning-only.
    blocking = bool(failures) or (strays_block and bool(warnings))
    if blocking:
        if args.enforce:
            sys.exit(1)
        print("\nReport mode: exiting 0. Run with --enforce to make these block CI.")


if __name__ == "__main__":
    main()
