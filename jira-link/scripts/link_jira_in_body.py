#!/usr/bin/env python3
"""Make the Jira issue key clickable in a GitHub PR body.

Reads the body from --body-file (or stdin), writes the updated body to stdout,
and prints a one-word status to stderr:

  linked     an existing bare mention of the key became a markdown link
  inserted   the key was not mentioned, so a `Jira: [KEY](url)` line was prepended
  unchanged  the key already links to the issue; nothing to do

Mentions inside code fences, inline code, existing markdown links, autolinks and
raw URLs are left alone. Only the first bare mention is linked — repeating the
link on every mention adds noise without adding reach.

Usage:
  gh pr view 123 --repo owner/repo --json body -q .body \
    | link_jira_in_body.py --key PROJ-123 --jira-url https://acme.atlassian.net \
    > /tmp/body.md
"""

import argparse
import re
import sys

PROTECTED = re.compile(
    r"```.*?```"                 # fenced code block
    r"|~~~.*?~~~"                # fenced code block (tilde)
    r"|`[^`\n]*`"                # inline code
    r"|!?\[[^\]]*\]\([^)]*\)"    # markdown link or image
    r"|<[^>\s]+>"                # autolink or html tag
    r"|https?://\S+",            # bare URL
    re.DOTALL,
)


def protected_spans(text):
    return [m.span() for m in PROTECTED.finditer(text)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", required=True, help="Jira issue key, e.g. PROJ-123")
    parser.add_argument(
        "--jira-url",
        required=True,
        help="Jira base URL, e.g. https://acme.atlassian.net (no trailing slash needed)",
    )
    parser.add_argument("--body-file", help="File holding the PR body; defaults to stdin")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Link every bare mention instead of only the first one",
    )
    args = parser.parse_args()

    key = args.key.strip().upper()
    base = args.jira_url.strip().rstrip("/")
    if not re.match(r"^https?://\S+$", base):
        print(
            f"error: --jira-url must be an absolute http(s) URL, got {base!r}",
            file=sys.stderr,
        )
        return 2
    url = f"{base}/browse/{key}"

    if args.body_file:
        with open(args.body_file, encoding="utf-8") as handle:
            body = handle.read()
    else:
        body = sys.stdin.read()

    # Already reachable? A markdown link or a raw URL pointing at /browse/KEY.
    already = re.search(
        rf"/browse/{re.escape(key)}(?![A-Za-z0-9-])", body, re.IGNORECASE
    )
    if already:
        sys.stdout.write(body)
        print("unchanged", file=sys.stderr)
        return 0

    key_re = re.compile(
        rf"(?<![A-Za-z0-9-]){re.escape(key)}(?![A-Za-z0-9-])", re.IGNORECASE
    )
    spans = protected_spans(body)

    def is_protected(index):
        return any(start <= index < end for start, end in spans)

    out = []
    cursor = 0
    linked = 0
    for match in key_re.finditer(body):
        if is_protected(match.start()):
            continue
        out.append(body[cursor : match.start()])
        out.append(f"[{key}]({url})")
        cursor = match.end()
        linked += 1
        if not args.all:
            break

    if linked:
        out.append(body[cursor:])
        sys.stdout.write("".join(out))
        print("linked", file=sys.stderr)
        return 0

    # No bare mention anywhere: prepend a one-line reference.
    line = f"Jira: [{key}]({url})"
    body = body.lstrip("\n")
    sys.stdout.write(f"{line}\n\n{body}" if body else f"{line}\n")
    print("inserted", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
