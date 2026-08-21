"""Read and write the version fields declared in `.claude/release.json`.

Shared by collect_changes.py (reads) and bump_version.py (writes). Every writer edits in place
with a targeted substitution so the rest of the file — comments, key order, indentation — survives
untouched; a version bump that reformats package.json produces a diff nobody wants to review.

Supported `format` values: properties, json, plist, gradle-kts, gradle-groovy, toml, yaml, text,
regex. A file nothing here parses can always be declared as `regex` with an explicit pattern.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


class VersionFileError(Exception):
    pass


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise VersionFileError(f"missing version file: {path}") from exc


def _last_key(key: str) -> str:
    return key.split(".")[-1] if key else ""


def _patterns(fmt: str, key: str, custom: str | None):
    """Return a list of (regex, group_index) candidates for `fmt`/`key`."""
    k = re.escape(_last_key(key))
    if fmt == "regex":
        if not custom:
            raise VersionFileError("format 'regex' requires a `pattern` with one capture group")
        return [(re.compile(custom, re.M), 1)]
    if fmt == "properties":
        return [(re.compile(rf"^(\s*{k}\s*=\s*)(.+?)(\s*)$", re.M), 2)]
    if fmt == "json":
        return [(re.compile(rf'("{k}"\s*:\s*")([^"]*)(")'), 2),
                (re.compile(rf'("{k}"\s*:\s*)(\d+)()'), 2)]
    if fmt == "plist":
        return [(re.compile(rf"(<key>{k}</key>\s*<string>)([^<]*)(</string>)"), 2)]
    if fmt == "gradle-kts":
        return [(re.compile(rf'({k}\s*=\s*")([^"]*)(")'), 2),
                (re.compile(rf"({k}\s*=\s*)(\d+)()"), 2)]
    if fmt == "gradle-groovy":
        return [(re.compile(rf'({k}\s+")([^"]*)(")'), 2),
                (re.compile(rf"({k}\s+)(\d+)()"), 2),
                (re.compile(rf'({k}\s*=\s*")([^"]*)(")'), 2),
                (re.compile(rf"({k}\s*=\s*)(\d+)()"), 2)]
    if fmt == "toml":
        return [(re.compile(rf'^(\s*{k}\s*=\s*")([^"]*)(")', re.M), 2)]
    if fmt == "yaml":
        return [(re.compile(rf"^(\s*{k}\s*:\s*)(\S+)(\s*)$", re.M), 2)]
    raise VersionFileError(f"unsupported version file format: {fmt}")


def read_value(entry: dict, root: Path) -> str:
    """Current raw value of one `version.files[]` entry."""
    path = root / entry["path"]
    fmt = entry.get("format", "text")
    text = _read_text(path)
    if fmt == "text":
        return text.strip()
    for rx, gi in _patterns(fmt, entry.get("key", ""), entry.get("pattern")):
        m = rx.search(text)
        if m:
            return m.group(gi).strip().strip('"')
    if fmt == "json":  # last resort: walk the parsed document
        doc = json.loads(text)
        cur = doc
        for part in entry.get("key", "").split("."):
            cur = cur[part]
        return str(cur)
    raise VersionFileError(f"{entry['path']}: could not find `{entry.get('key')}` as {fmt}")


def write_value(entry: dict, root: Path, new_value: str) -> tuple[str, str]:
    """Set one entry to `new_value`. Returns (old, new). Raises if the field isn't found."""
    path = root / entry["path"]
    fmt = entry.get("format", "text")
    text = _read_text(path)

    if fmt == "text":
        old = text.strip()
        path.write_text(new_value + "\n", encoding="utf-8")
        return old, new_value

    for rx, gi in _patterns(fmt, entry.get("key", ""), entry.get("pattern")):
        m = rx.search(text)
        if not m:
            continue
        old = m.group(gi)
        start, end = m.span(gi)
        path.write_text(text[:start] + new_value + text[end:], encoding="utf-8")
        return old.strip().strip('"'), new_value

    raise VersionFileError(
        f"{entry['path']}: could not find `{entry.get('key')}` as {fmt} — check the manifest, "
        "or declare the file as format 'regex' with an explicit pattern"
    )


def split_semver_counter(value: str) -> tuple[str, str | None]:
    """`1.2.3+45` -> ("1.2.3", "45"); plain values come back with None (Flutter pubspec style)."""
    if "+" in value:
        head, _, tail = value.partition("+")
        return head, tail
    return value, None


def bump_semver(current: str, level: str) -> str:
    """Next version for `level` in major|minor|patch. 0.x keeps breaking changes in minor,
    which is what SemVer says about a line that hasn't committed to stability yet."""
    parts = [int(p) for p in re.findall(r"\d+", current)[:3]]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts
    if level == "major":
        if major == 0:
            return f"0.{minor + 1}.0"
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"
