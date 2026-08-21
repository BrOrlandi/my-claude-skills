#!/usr/bin/env python3
"""What goes into the next release of one app: the range, the commits, the version.

    python3 collect_changes.py                      # every app in the manifest
    python3 collect_changes.py --app android        # one app
    python3 collect_changes.py --app web --json     # machine-readable
    python3 collect_changes.py --since v1.4.0       # override the resolved anchor

Reads `.claude/release.json` (see references/manifest-schema.md), resolves each app's anchor to a
git range, lists the commits that touched that app's paths, classifies them by conventional-commit
type, marks breaking changes, reads the current version, and proposes the next one.

If the repo's layout defeats this script, the equivalent by hand is:

    git tag --list 'android-v*' --sort=-v:refname | head -1     # anchor: tag
    git log <tag>..HEAD --format='%h %ad %s' --date=short -- android-app
    git log --after=2026-08-14 --format='%h %ad %s' --date=short -- app packages

Falling back to those beats guessing a range: a wrong range silently drops entries or repeats
ones already published.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from version_files import VersionFileError, bump_semver, read_value, split_semver_counter  # noqa: E402

# Types that describe a change to the product, and those that describe a change to the tree.
RELEASE_WORTHY = {"feat", "fix", "perf", "revert"}
REVIEW = {"refactor", "style", "build"}  # may hide behavior changes — read the diff before deciding
SKIP = {"docs", "chore", "test", "ci", "deps"}

PT_MONTHS = {
    "janeiro": 1, "fevereiro": 2, "março": 3, "marco": 3, "abril": 4, "maio": 5, "junho": 6,
    "julho": 7, "agosto": 8, "setembro": 9, "outubro": 10, "novembro": 11, "dezembro": 12,
}
CC_RE = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<subject>.+)$", re.I)


def git(*args: str, root: Path | None = None) -> str:
    out = subprocess.run(["git", *args], capture_output=True, text=True, cwd=root)
    if out.returncode != 0:
        return ""
    return out.stdout.strip()


def repo_root(start: Path) -> Path:
    top = git("rev-parse", "--show-toplevel", root=start)
    return Path(top) if top else start


def latest_tag(prefix: str, root: Path) -> str | None:
    for sort in ("-v:refname", "-creatordate"):
        tags = git("tag", "--list", f"{prefix}*", f"--sort={sort}", root=root).splitlines()
        tags = [t for t in tags if t.strip()]
        if tags:
            return tags[0].strip()
    return None


def parse_changelog_head(path: Path) -> tuple[str | None, str | None]:
    """(version, iso-date) of the newest entry of a markdown changelog, best effort."""
    if not path.exists():
        return None, None
    version = iso = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("#"):
            continue
        m = re.search(r"\[?v?(\d+\.\d+(?:\.\d+)?)\]?", line)
        if m and version is None:
            version = m.group(1)
        d = re.search(r"(\d{4})-(\d{2})-(\d{2})", line)
        if d and iso is None:
            iso = "-".join(d.groups())
        if iso is None:
            pt = re.search(r"(\d{1,2})\s+de\s+([A-Za-zçÇãáéíóúâêô]+)\s+de\s+(\d{4})", line, re.I)
            if pt:
                mon = PT_MONTHS.get(pt.group(2).lower())
                if mon:
                    iso = f"{pt.group(3)}-{mon:02d}-{int(pt.group(1)):02d}"
        if version or iso:
            break
    return version, iso


def scan_code_changelog_date(path: Path) -> str | None:
    """Newest date inside a code-embedded changelog (TS array, Kotlin list, ...)."""
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", text)
    if m:
        return "-".join(m.groups())
    pt = re.search(r"(\d{1,2})\s+de\s+([A-Za-zçÇãáéíóúâêô]+)\s+de\s+(\d{4})", text, re.I)
    if pt:
        mon = PT_MONTHS.get(pt.group(2).lower())
        if mon:
            return f"{pt.group(3)}-{mon:02d}-{int(pt.group(1)):02d}"
    return None


def resolve_anchor(app: dict, root: Path, since: str | None) -> dict:
    """How far back to look, and how that was decided."""
    if since:
        kind = "date" if re.fullmatch(r"\d{4}-\d{2}-\d{2}", since) else "ref"
        return {"how": f"--since {since}", kind: since}

    ver = app.get("version", {}) or {}
    anchor = ver.get("anchor", "tag")
    prefix = ver.get("tagPrefix", "v")
    logs = app.get("changelogs") or []
    primary = root / logs[0]["path"] if logs else None

    if anchor == "tag":
        tag = latest_tag(prefix, root)
        if tag:
            return {"how": f"tag {tag}", "ref": tag}
    if anchor in ("changelog-version", "tag"):
        if primary:
            v, d = parse_changelog_head(primary)
            if v:
                tag = f"{prefix}{v}"
                if git("rev-parse", "--verify", "--quiet", tag, root=root):
                    return {"how": f"changelog {v} -> tag {tag}", "ref": tag}
            if d:
                return {"how": f"changelog entry dated {d}", "date": d}
    if anchor == "changelog-date" and primary:
        d = parse_changelog_head(primary)[1] or scan_code_changelog_date(primary)
        if d:
            return {"how": f"newest changelog entry dated {d}", "date": d}
    if anchor == "manifest":
        last = ver.get("lastRelease") or {}
        if last.get("date"):
            return {"how": f"manifest lastRelease {last.get('version', '')} ({last['date']})",
                    "date": last["date"]}

    return {"how": "no anchor found — showing recent history, confirm the range with the user",
            "fallback": True}


def log_commits(app: dict, root: Path, anchor: dict, limit: int) -> list[dict]:
    fmt = "%H%x1f%ad%x1f%s%x1f%b%x1e"
    args = ["log", f"--format={fmt}", "--date=short", "--no-merges"]
    if anchor.get("ref"):
        args.append(f"{anchor['ref']}..HEAD")
    elif anchor.get("date"):
        args.append(f"--after={anchor['date']}")
    else:
        args.append(f"-{limit}")
    paths = app.get("paths") or []
    if paths:
        args += ["--", *paths]

    raw = git(*args, root=root)
    commits = []
    for chunk in raw.split("\x1e"):
        chunk = chunk.strip("\n")
        if not chunk.strip():
            continue
        parts = chunk.split("\x1f")
        sha, cdate, subject = parts[0], parts[1], parts[2]
        body = parts[3] if len(parts) > 3 else ""
        m = CC_RE.match(subject)
        ctype = (m.group("type").lower() if m else "")
        breaking = bool(m and m.group("bang")) or "BREAKING CHANGE" in body
        if ctype in RELEASE_WORTHY:
            verdict = "include"
        elif ctype in REVIEW:
            verdict = "read-the-diff"
        elif ctype in SKIP:
            verdict = "skip"
        else:
            verdict = "read-the-diff"  # unconventional subject: judge it from the change itself
        commits.append({
            "sha": sha[:9],
            "date": cdate,
            "type": ctype or None,
            "scope": (m.group("scope") if m else None),
            "breaking": breaking,
            "subject": (m.group("subject") if m else subject),
            "verdict": "include" if breaking else verdict,
        })
    return commits


def current_version(app: dict, root: Path) -> dict:
    out = {"semver": None, "counters": {}, "errors": []}
    for entry in (app.get("version", {}) or {}).get("files", []) or []:
        label = f"{entry['path']}:{entry.get('key', '')}"
        try:
            raw = read_value(entry, root)
        except VersionFileError as exc:
            out["errors"].append(str(exc))
            continue
        if entry.get("kind") == "counter":
            out["counters"][label] = raw
        else:
            sem, counter = split_semver_counter(raw)
            out["semver"] = out["semver"] or sem
            if counter:
                out["counters"][label + " (+n)"] = counter
    return out


def propose(commits: list[dict], cur: str | None, policy: str = "conventional-commits") -> dict:
    included = [c for c in commits if c["verdict"] == "include"]
    if policy == "none" or not cur:
        # A unit with no version number (a date-grouped changelog, say) has nothing to bump.
        return {"level": None, "version": None, "included": len(included), "total": len(commits)}
    level = "patch"
    if any(c["breaking"] for c in included):
        level = "major"
    elif any(c["type"] == "feat" for c in included):
        level = "minor"
    return {"level": level, "version": bump_semver(cur, level),
            "included": len(included), "total": len(commits)}


def consistency_warnings(app: dict, root: Path, cur: dict, bump: dict) -> list[str]:
    """Cheap cross-checks that catch the two mistakes this flow actually makes: writing a second
    entry for a version that already has one, and releasing from a repo whose last release was
    never tagged."""
    warns: list[str] = []
    ver = app.get("version", {}) or {}
    prefix = ver.get("tagPrefix", "v")
    sem = cur.get("semver")

    tag = latest_tag(prefix, root)
    if tag and sem:
        tag_ver = tag[len(prefix):] if tag.startswith(prefix) else tag.lstrip("v")
        if _as_tuple(sem) > _as_tuple(tag_ver):
            warns.append(
                f"version files say {sem} but the newest tag is {tag} — either {sem} shipped "
                "untagged, or its bump is already staged; confirm before bumping again")

    logs = app.get("changelogs") or []
    if logs and sem:
        head_ver = parse_changelog_head(root / logs[0]["path"])[0]
        if head_ver and _as_tuple(head_ver) >= _as_tuple(sem):
            warns.append(
                f"{logs[0]['path']} already has an entry for {head_ver} — add to that entry or "
                "bump the version, don't write a second one for the same release")

    if not logs:
        warns.append("no changelog target configured — this app only carries a version number")

    if (bump or {}).get("cadence") == "per-commit":
        warns.append("bump.cadence is per-commit — the bump belongs in the same commit as the "
                     "change it describes, not in a release commit of its own")

    dirty = [ln for ln in git("status", "--porcelain", root=root).splitlines() if ln.strip()]
    touched = {e["path"] for e in (ver.get("files") or [])} | {c["path"] for c in logs}
    pending = [ln for ln in dirty if any(t in ln for t in touched)]
    if pending:
        warns.append("uncommitted changes already touch version/changelog files: "
                     + ", ".join(ln[3:] for ln in pending))
    return warns


def _as_tuple(v: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3]) or (0,)


def report(app: dict, root: Path, since: str | None, limit: int, bump: dict | None = None) -> dict:
    anchor = resolve_anchor(app, root, since)
    commits = log_commits(app, root, anchor, limit)
    cur = current_version(app, root)
    warnings = consistency_warnings(app, root, cur, bump or {})
    if anchor.get("date"):
        same_day = [c for c in commits if c["date"] == anchor["date"]]
        if same_day:
            warnings.append(
                f"{len(same_day)} commit(s) are dated {anchor['date']}, the same day as the entry the "
                "range was anchored on — they may already be described there. Check that entry before "
                "writing them again, or add to it instead of opening a new one")
    return {
        "warnings": warnings,
        "app": app.get("id"),
        "label": app.get("label"),
        "kind": app.get("kind"),
        "paths": app.get("paths") or ["<whole repo>"],
        "anchor": anchor,
        "current": cur,
        "proposal": propose(commits, cur["semver"], (bump or {}).get("policy", "conventional-commits")),
        "commits": commits,
        "changelogs": [c.get("path") for c in (app.get("changelogs") or [])],
        "publish": [p.get("channel") for p in (app.get("publish") or [])],
        "today": date.today().isoformat(),
    }


def human(rep: dict) -> None:
    print(f"\n=== {rep['app']} — {rep['label'] or ''} ({rep['kind'] or '?'})")
    print(f"paths      : {', '.join(rep['paths'])}")
    print(f"range      : {rep['anchor']['how']}")
    cur = rep["current"]
    print(f"version    : {cur['semver'] or '(none found)'}"
          + (f"   counters: {cur['counters']}" if cur["counters"] else ""))
    for err in cur["errors"]:
        print(f"  ! {err}")
    p = rep["proposal"]
    head = f"{p['level']} -> {p['version']}" if p["level"] else "no version to bump"
    print(f"proposal   : {head}  ({p['included']} release-worthy of {p['total']} commits)")
    print(f"changelogs : {', '.join(rep['changelogs']) or '(none configured)'}")
    print(f"publish    : {', '.join(rep['publish']) or '(nothing published)'}")
    for w in rep.get("warnings", []):
        print(f"  ~ {w}")
    if not rep["commits"]:
        print("\nno commits in range — nothing to release")
        return
    print("\n  verdict        type      sha        date        subject")
    for c in rep["commits"]:
        flag = "!" if c["breaking"] else " "
        print(f"  {c['verdict']:<14} {(c['type'] or '-'):<9} {c['sha']:<10} {c['date']}  {flag}{c['subject']}")
    print("\nread-the-diff = judge from `git show --stat <sha>` before writing about it")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=".claude/release.json")
    ap.add_argument("--app", help="app id from the manifest (default: all)")
    ap.add_argument("--since", help="override the anchor: a git ref or YYYY-MM-DD")
    ap.add_argument("--limit", type=int, default=30, help="commits to show when no anchor resolves")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = repo_root(Path.cwd())
    mpath = Path(args.manifest)
    if not mpath.is_absolute():
        mpath = root / mpath
    if not mpath.exists():
        print(f"no manifest at {mpath} — run the release skill's setup mode first", file=sys.stderr)
        return 2

    manifest = json.loads(mpath.read_text(encoding="utf-8"))
    apps = manifest.get("apps") or []
    if args.app:
        apps = [a for a in apps if a.get("id") == args.app]
        if not apps:
            print(f"no app `{args.app}` in {mpath}", file=sys.stderr)
            return 2

    bump = manifest.get("bump", {})
    reports = [report(a, root, args.since, args.limit, bump) for a in apps]
    if args.json:
        print(json.dumps({"bump": manifest.get("bump", {}), "reports": reports},
                         indent=2, ensure_ascii=False))
    else:
        for rep in reports:
            human(rep)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
