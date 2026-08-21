#!/usr/bin/env python3
"""Write a new version into every file the manifest says carries it.

    python3 bump_version.py --app android --version 1.2.0
    python3 bump_version.py --app android --level minor          # compute from the current value
    python3 bump_version.py --app web --version 1.2.0 --dry-run

Semantic fields (`kind: semver`) are set to the new version. Counters (`kind: counter` —
`versionCode`, `CFBundleVersion`) increment instead: they order uploads for a store, must always
grow, and may never repeat, so they move even when the semantic version doesn't. A counter entry
with an `offset` follows the base counter (a Wear OS module at +1000, which Play needs because two
uploads under one applicationId cannot share a code).

Editing is in place and targeted, so comments, key order and formatting survive — the diff shows
the version and nothing else. Read that diff: version files are small, and a wrong edit here is
the one mistake that reaches every artifact.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from version_files import (  # noqa: E402
    VersionFileError, bump_semver, read_value, split_semver_counter, write_value,
)


def repo_root(start: Path) -> Path:
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, cwd=start)
    return Path(out.stdout.strip()) if out.returncode == 0 else start


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=".claude/release.json")
    ap.add_argument("--app", required=True)
    ap.add_argument("--version", help="explicit new semantic version, e.g. 1.2.0")
    ap.add_argument("--level", choices=["major", "minor", "patch"], help="derive it from the current value")
    ap.add_argument("--counter-step", type=int, default=1)
    ap.add_argument("--set-counter", type=int, help="force the base counter instead of incrementing")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.version and not args.level:
        print("pass --version or --level", file=sys.stderr)
        return 2

    root = repo_root(Path.cwd())
    mpath = Path(args.manifest)
    if not mpath.is_absolute():
        mpath = root / mpath
    if not mpath.exists():
        print(f"no manifest at {mpath} — run the release skill's setup mode first", file=sys.stderr)
        return 2

    manifest = json.loads(mpath.read_text(encoding="utf-8"))
    app = next((a for a in manifest.get("apps", []) if a.get("id") == args.app), None)
    if app is None:
        print(f"no app `{args.app}` in {mpath}", file=sys.stderr)
        return 2

    entries = (app.get("version", {}) or {}).get("files") or []
    if not entries:
        print(f"app `{args.app}` declares no version files — nothing to bump", file=sys.stderr)
        return 1

    sem_entries = [e for e in entries if e.get("kind", "semver") == "semver"]
    counters = [e for e in entries if e.get("kind") == "counter"]

    # Resolve the new semantic version.
    new_version = args.version
    if not new_version:
        current = None
        for e in sem_entries:
            try:
                current = split_semver_counter(read_value(e, root))[0]
                break
            except VersionFileError:
                continue
        if not current:
            print("could not read a current version to apply --level to", file=sys.stderr)
            return 1
        new_version = bump_semver(current, args.level)

    # Resolve the base counter: the counter entry without an offset leads, the rest follow it.
    base_new = None
    if counters:
        base_entry = next((c for c in counters if not c.get("offset")), counters[0])
        try:
            base_cur = int(str(read_value(base_entry, root)).strip() or 0)
        except (VersionFileError, ValueError) as exc:
            print(f"! {exc}", file=sys.stderr)
            base_cur = 0
        base_new = args.set_counter if args.set_counter is not None else base_cur + args.counter_step

    changes = []
    for e in entries:
        is_counter = e.get("kind") == "counter"
        if is_counter:
            value = str(base_new + int(e.get("offset") or 0))
        else:
            # Flutter-style "1.2.3+45" keeps its build number, incremented alongside.
            try:
                _, tail = split_semver_counter(read_value(e, root))
            except VersionFileError:
                tail = None
            value = f"{new_version}+{int(tail) + args.counter_step}" if tail else new_version

        label = f"{e['path']}:{e.get('key', '(file)')}"
        if args.dry_run:
            try:
                old = read_value(e, root)
            except VersionFileError as exc:
                print(f"! {exc}", file=sys.stderr)
                continue
            changes.append((label, old, value))
            continue
        try:
            old, new = write_value(e, root, value)
        except VersionFileError as exc:
            print(f"! {exc}", file=sys.stderr)
            return 1
        changes.append((label, old, new))

    verb = "would set" if args.dry_run else "set"
    print(f"{args.app}: {verb} version {new_version}"
          + (f", base counter {base_new}" if base_new is not None else ""))
    for label, old, new in changes:
        mark = " " if old == new else "*"
        print(f"  {mark} {label}: {old} -> {new}")
    if not args.dry_run:
        print("\nreview it before committing:  git diff -- "
              + " ".join(sorted({e["path"] for e in entries})))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
