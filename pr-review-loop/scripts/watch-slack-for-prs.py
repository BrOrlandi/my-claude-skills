#!/usr/bin/env python3
"""Wait until a Slack message hands the reviewer a pull request, then print it and exit.

A message counts when it holds a GitHub PR URL and it is
- in a direct message with the reviewer, or
- in a group DM or a channel and mentions the reviewer (`<@USER_ID>`).
The reviewer's own messages never count.

It polls Slack search (`slackcli search messages`, the reviewer's own token) every INTERVAL seconds and exits
as soon as a poll finds something new, so the Claude Code session that launched it in the background wakes
up and runs `/pr-review-loop` on each PR. Messages already handed over are remembered in STATE, so a restart
never hands the same message twice.

Usage: watch-slack-for-prs.py [--since <unix ts>]
  --since   only messages after this time (default: the last one handed over, else now)

Environment (optional):
  INTERVAL   seconds between polls (default 300)
  MAX_WAIT   seconds before giving up (default 86400)
  SLACK_WORKSPACE  slackcli workspace name or id (default: slackcli's default)
  PR_LOOP_STATE    state file (default ~/.claude/pr-review-loop/slack-seen.json)

Output (stdout), one line per PR, then exit 0:
  PR <url> | from <user id> | in <channel name or "DM"> | <permalink>
or `TIMEOUT` (exit 1). Errors reaching Slack go to stderr and the poll is retried.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

PR_URL = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/pull/\d+")
INTERVAL = int(os.environ.get("INTERVAL", "300"))
MAX_WAIT = int(os.environ.get("MAX_WAIT", "86400"))
STATE = Path(os.environ.get("PR_LOOP_STATE", Path.home() / ".claude" / "pr-review-loop" / "slack-seen.json"))
WORKSPACE = ["--workspace", os.environ["SLACK_WORKSPACE"]] if os.environ.get("SLACK_WORKSPACE") else []


def slackcli(*args: str) -> str:
    return subprocess.run(
        ["slackcli", *args, *WORKSPACE], check=True, capture_output=True, text=True, timeout=120
    ).stdout


def my_user_id() -> str:
    out = slackcli("auth", "whoami")
    found = re.search(r"\((U[A-Z0-9]+)\)", out)
    if not found:
        raise SystemExit("could not read the Slack user id from `slackcli auth whoami`")
    return found.group(1)


def load_state() -> dict:
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {"seen": [], "last_ts": None}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    state["seen"] = state["seen"][-2000:]
    STATE.write_text(json.dumps(state))


def search(since: float) -> list[dict]:
    # `after:` is a date and excludes that day, so ask from the day before and filter by ts below.
    day = (datetime.fromtimestamp(since, timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
    out = slackcli("search", "messages", f'"/pull/" after:{day}', "--limit", "100", "--sort", "timestamp", "--json")
    data = json.loads(out)
    return data.get("matches") or []


def handed_over(message: dict, me: str) -> bool:
    if message.get("user") == me:
        return False
    channel = message.get("channel") or {}
    if channel.get("is_im"):
        return True
    return f"<@{me}>" in (message.get("text") or "")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--since", type=float)
    args = parser.parse_args()

    me = my_user_id()
    state = load_state()
    since = args.since or state.get("last_ts") or time.time()
    started = time.monotonic()

    while time.monotonic() - started < MAX_WAIT:
        try:
            matches = search(since)
        except (subprocess.SubprocessError, ValueError, OSError) as exc:
            print(f"slack search failed, retrying: {exc}", file=sys.stderr)
            matches = []
        found = []
        for message in matches:
            ts = str(message.get("ts") or "")
            if not ts or float(ts) <= since or ts in state["seen"]:
                continue
            if not handed_over(message, me):
                continue
            urls = sorted(set(PR_URL.findall(message.get("text") or "")))
            if not urls:
                continue
            channel = message.get("channel") or {}
            where = "DM" if channel.get("is_im") else (channel.get("name") or channel.get("id") or "?")
            for url in urls:
                found.append(f"PR {url} | from {message.get('user')} | in {where} | {message.get('permalink', '')}")
            state["seen"].append(ts)
            state["last_ts"] = max(float(ts), float(state.get("last_ts") or 0))
        if found:
            save_state(state)
            print("\n".join(found))
            return 0
        time.sleep(INTERVAL)

    print("TIMEOUT")
    return 1


if __name__ == "__main__":
    sys.exit(main())
