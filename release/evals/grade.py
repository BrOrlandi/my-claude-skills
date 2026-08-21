#!/usr/bin/env python3
"""Grade one eval run of the `release` skill: mechanical checks, one per assertion.

    python3 grade.py <iteration-dir> [--write]

For each eval/<config>/ it reads the resulting repo plus the run's outputs (changes.diff,
status.txt, summary.md) and writes grading.json with {text, passed, evidence} per assertion —
the field names the eval viewer expects.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

EVALS = ["eval-1-setup-version-only", "eval-2-setup-monorepo", "eval-3-notes-inapp-ptbr"]
CONFIGS = ["with_skill", "without_skill"]
PT_MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto",
             "setembro", "outubro", "novembro", "dezembro"]


def git(repo: Path, *args: str) -> str:
    r = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    return r.stdout.strip()


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def manifest(repo: Path) -> dict | None:
    p = repo / ".claude" / "release.json"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def version_pairs(app: dict) -> set[tuple[str, str]]:
    return {(f.get("path", ""), f.get("key", "")) for f in (app.get("version", {}) or {}).get("files", []) or []}


def app_by(m: dict, *needles: str) -> dict | None:
    for a in m.get("apps", []):
        blob = json.dumps(a, ensure_ascii=False).lower()
        if all(n.lower() in blob for n in needles):
            return a
    return None


def top_entry(ts: str) -> str:
    """The first object literal inside `releases ... = [`."""
    i = ts.find("releases")
    i = ts.find("[", i)
    if i < 0:
        return ""
    j = ts.find("{", i)
    if j < 0:
        return ""
    depth, k = 0, j
    while k < len(ts):
        if ts[k] == "{":
            depth += 1
        elif ts[k] == "}":
            depth -= 1
            if depth == 0:
                return ts[j:k + 1]
        k += 1
    return ""


def brackets_balanced(src: str) -> bool:
    depth = {"{": 0, "[": 0, "(": 0}
    pairs = {"}": "{", "]": "[", ")": "("}
    i, n = 0, len(src)
    quote = None
    while i < n:
        c = src[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "'\"`":
            quote = c
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            i = src.find("\n", i)
            if i < 0:
                break
        elif c in depth:
            depth[c] += 1
        elif c in pairs:
            depth[pairs[c]] -= 1
        i += 1
    return all(v == 0 for v in depth.values())


def grade_e1(repo: Path, out: Path) -> list[tuple[bool, str]]:
    m = manifest(repo)
    claude = read(repo / "CLAUDE.md")
    res = []
    res.append((bool(m and m.get("manifestVersion") and m.get("apps")),
                f"manifest parsed={bool(m)}, apps={len((m or {}).get('apps', []))}"))
    pairs = set().union(*[version_pairs(a) for a in (m or {}).get("apps", [])]) if m else set()
    res.append((pairs == {("package.json", "version")}, f"version files: {sorted(pairs)}"))
    cadence = ((m or {}).get("bump") or {}).get("cadence")
    res.append((cadence == "per-commit", f"bump.cadence={cadence!r}"))
    empties = all(not a.get("changelogs") and not a.get("publish") for a in (m or {}).get("apps", [])) if m else False
    res.append((empties, "changelogs/publish empty for every app" if empties else
                f"non-empty: {[(a.get('id'), a.get('changelogs'), a.get('publish')) for a in (m or {}).get('apps', [])]}"))
    found = [str(p.relative_to(repo)) for p in repo.rglob("CHANGELOG*")
             if ".git/" not in str(p) and "node_modules" not in str(p)]
    found += [str(p.relative_to(repo)) for p in repo.rglob("HISTORY*")
              if ".git/" not in str(p) and "node_modules" not in str(p)]
    res.append((not found, f"history files present: {found or 'none'}"))
    ok = ".claude/release.json" in claude and "package.json" in claude
    res.append((ok, f"CLAUDE.md mentions manifest={'.claude/release.json' in claude}, package.json={'package.json' in claude}"))
    kept = "Every commit raises" in claude and "patch" in claude and "minor" in claude
    res.append((kept, "per-commit bump rule and its patch/minor/major bullets survived"
                if kept else "the repo's existing bump rule was dropped or contradicted"))
    tags = git(repo, "tag")
    pkg = json.loads(read(repo / "package.json") or "{}").get("version")
    commits = [c for c in git(repo, "log", "--oneline", "8e607f9..HEAD").splitlines() if c]
    bumped = pkg != "1.2.2"
    ok = not tags and (not bumped or bool(commits))
    res.append((ok, f"tags={tags or 'none'}, version={pkg} (base 1.2.2), commits={len(commits)}"
                    + (" — bump rides with a commit, as the repo requires" if bumped and commits else "")))
    return res


def grade_e2(repo: Path, out: Path) -> list[tuple[bool, str]]:
    m = manifest(repo)
    claude = read(repo / "CLAUDE.md")
    summary = read(out / "summary.md")
    res = []
    android = app_by(m, "android") if m else None
    macos = app_by(m, "macos-app") if m else None
    res.append((bool(m) and bool(android) and bool(macos),
                f"apps={[a.get('id') for a in (m or {}).get('apps', [])]}"))
    ap = version_pairs(android) if android else set()
    kinds = {(f.get("key"), f.get("kind")) for f in ((android or {}).get("version", {}) or {}).get("files", []) or []}
    res.append((("android-app/version.properties", "versionName") in ap
                and ("versionName", "semver") in kinds and ("versionCode", "counter") in kinds,
                f"android version files={sorted(ap)}, kinds={sorted(kinds)}"))
    mp = version_pairs(macos) if macos else set()
    res.append((any("Info.plist" in p and k == "CFBundleShortVersionString" for p, k in mp)
                and any("Info.plist" in p and k == "CFBundleVersion" for p, k in mp),
                f"macos version files={sorted(mp)}"))
    apx = ((android or {}).get("version", {}) or {}).get("tagPrefix")
    mpx = ((macos or {}).get("version", {}) or {}).get("tagPrefix")
    res.append((bool(apx) and bool(mpx) and apx != mpx and "android" in (apx or "").lower(),
                f"tag prefixes: android={apx!r}, macos={mpx!r}"))
    alogs = {c.get("path"): c for c in ((android or {}).get("changelogs") or [])}
    store = alogs.get("playstore/release-notes.md", {})
    res.append(("android-app/CHANGELOG.md" in alogs and "playstore/release-notes.md" in alogs
                and store.get("maxChars") in (500,) and str(store.get("language", "")).lower().startswith("pt"),
                f"android changelogs={list(alogs)}, store={ {k: store.get(k) for k in ('maxChars', 'language')} }"))
    mlogs = [c.get("path") for c in ((macos or {}).get("changelogs") or [])]
    res.append(("CHANGELOG.md" in mlogs, f"macos changelogs={mlogs}"))
    missing = []
    for a in (m or {}).get("apps", []):
        for f in (a.get("version", {}) or {}).get("files", []) or []:
            if f.get("path") and not (repo / f["path"]).exists():
                missing.append(f["path"])
        for c in a.get("changelogs") or []:
            if c.get("path") and not (repo / c["path"]).exists():
                missing.append(c["path"])
        for d in a.get("docs") or []:
            if not (repo / d.split("#")[0]).exists():
                missing.append(d)
    res.append((not missing, f"non-existent paths: {missing or 'none'}"))
    ok = all(t in claude for t in ("version.properties", "Info.plist", "android-v"))
    res.append((ok, f"CLAUDE.md mentions version.properties={'version.properties' in claude}, "
                    f"Info.plist={'Info.plist' in claude}, android-v={'android-v' in claude}"))
    changed = git(repo, "status", "--porcelain")
    tracked = [ln[3:] for ln in changed.splitlines()]
    forbidden = [f for f in tracked if f in ("CHANGELOG.md", "android-app/CHANGELOG.md",
                                             "playstore/release-notes.md", "android-app/version.properties",
                                             "macos-app/Resources/Info.plist")]
    res.append((not forbidden and not git(repo, "tag", "--list", "*1.6*"),
                f"release-owned files touched: {forbidden or 'none'}"))
    blob = summary + claude
    res.append(("1.5.0" in blob and "1.4.1" in blob,
                f"mentions 1.5.0={'1.5.0' in blob}, v1.4.1={'1.4.1' in blob}"))
    res.append(("RELEASING.md" in json.dumps(m or {}, ensure_ascii=False) or "RELEASING.md" in claude,
                "RELEASING.md referenced" if "RELEASING.md" in (json.dumps(m or {}) + claude) else "not referenced"))
    return res


def grade_e3(repo: Path, out: Path) -> list[tuple[bool, str]]:
    target = "packages/shared/src/screens/support-releases.ts"
    ts = read(repo / target)
    diff = read(out / "changes.diff")
    res = []
    noise = (".claude/skills/", ".claude/settings.local.json")
    changed = [ln[3:] for ln in git(repo, "status", "--porcelain").splitlines()]
    committed = git(repo, "diff", "--name-only", "6f4ad5c..HEAD").splitlines()
    touched = sorted({f for f in {*changed, *committed} if f and not f.startswith(noise)})
    res.append((touched == [target], f"files touched: {touched}"))
    entry = top_entry(ts)
    mdate = re.search(r"title:\s*'(\d{1,2}) de ([A-Za-zçÇãéíóúâêô]+) de (\d{4})'", entry or "")
    ok_date = False
    detail = "no parseable title in the top entry"
    if mdate:
        day, mon, year = int(mdate.group(1)), mdate.group(2).lower(), int(mdate.group(3))
        mi = PT_MONTHS.index(mon) + 1 if mon in PT_MONTHS else 0
        ok_date = (year, mi, day) > (2026, 8, 3)
        detail = f"top entry title = {mdate.group(0)[7:]}"
    res.append((ok_date, detail))
    target_diff = git(repo, "diff", "6f4ad5c", "--", target) or diff
    removed = [ln for ln in target_diff.splitlines() if ln.startswith("-") and not ln.startswith("---")]
    res.append((not removed, f"removed lines in diff: {len(removed)}"))
    descs = re.findall(r"description:\s*\n?\s*'((?:[^'\\]|\\.)*)'", entry or "")
    bolded = [d for d in descs if d.strip().startswith("**") and ":" in d]
    accented = [d for d in descs if re.search(r"[áàâãéêíóôõúçÁÉÍÓÚÃÂÔÇ]", d)]
    res.append((bool(descs) and len(bolded) == len(descs) and len(accented) >= max(1, len(descs) // 2),
                f"{len(descs)} descriptions, {len(bolded)} bold-titled, {len(accented)} with diacritics"))
    res.append((bool(descs) and entry.count("adminOnly") >= len(descs),
                f"adminOnly occurrences={entry.count('adminOnly')} for {len(descs)} descriptions"))
    banned = [w for w in ("ASO", "google-services", "método morto", "documentar", "refatora")
              if w.lower() in (entry or "").lower()]
    res.append((not banned, f"non-release-worthy topics found: {banned or 'none'}"))
    expected = [w for w in ("participaç", "cronometragem", "ao vivo", "nome completo", "regulamento",
                            "numerais", "briefing", "vestimenta")
                if w.lower() in (entry or "").lower()]
    res.append((len(expected) >= 2, f"real-change keywords matched: {expected}"))
    res.append((brackets_balanced(ts), "brackets balanced" if brackets_balanced(ts) else "unbalanced brackets"))
    leaks = []
    for block in re.findall(r"\{[^{}]*description[^{}]*\}", entry or "", re.S):
        if re.search(r"secretaria|sympla|auditoria|audit", block, re.I) and "adminOnly: true" not in block:
            leaks.append(block[:80])
    res.append((not leaks, f"admin topics shown to users: {leaks or 'none'}"))
    return res


GRADERS = {"eval-1-setup-version-only": grade_e1, "eval-2-setup-monorepo": grade_e2,
           "eval-3-notes-inapp-ptbr": grade_e3}


def main() -> int:
    root = Path(sys.argv[1])
    write = "--write" in sys.argv
    for name in EVALS:
        meta = json.loads((root / name / "eval_metadata.json").read_text())
        for cfg in CONFIGS:
            rundir = root / name / cfg
            repo, out = rundir / "repo", rundir / "outputs"
            if not repo.exists():
                continue
            try:
                results = GRADERS[name](repo, out)
            except Exception as exc:  # a run that produced nothing still gets a score
                results = [(False, f"grader error: {exc}")] * len(meta["assertions"])
            exps = [{"text": t, "passed": bool(p), "evidence": e}
                    for t, (p, e) in zip(meta["assertions"], results)]
            passed = sum(1 for e in exps if e["passed"])
            rate = round(passed / len(exps), 3) if exps else 0.0
            doc = {"eval_id": meta["eval_id"], "eval_name": name, "config": cfg,
                   "expectations": exps, "passed": passed, "total": len(exps),
                   "pass_rate": rate,
                   # `summary` is the shape scripts/aggregate_benchmark.py reads
                   "summary": {"passed": passed, "failed": len(exps) - passed,
                               "total": len(exps), "pass_rate": rate}}
            print(f"{name:32} {cfg:15} {passed}/{len(exps)}")
            for e in exps:
                if not e["passed"]:
                    print(f"    FAIL  {e['text'][:80]}  <- {e['evidence'][:110]}")
            if write:
                blob = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
                (rundir / "grading.json").write_text(blob)
                run1 = rundir / "run-1"          # the layout the aggregation script walks
                run1.mkdir(exist_ok=True)
                (run1 / "grading.json").write_text(blob)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
