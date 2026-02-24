#!/usr/bin/env python3
"""
pr_assets.py — Upload screenshots to a GitHub orphan branch and update PR descriptions.

Images are stored in the 'pr-assets' orphan branch of the current repo and served
via raw.githubusercontent.com, which preserves full quality (no compression) and
opens images inline in the browser instead of forcing a download.

Usage:
  pr_assets.py <filepath>
      Upload a single image to the pr-assets branch.
      Prints {"url": "https://raw.githubusercontent.com/..."} to stdout.

  pr_assets.py --setup
      Create the pr-assets orphan branch in the current repo (run once per repo).
      Safe to run multiple times — does nothing if the branch already exists.

  pr_assets.py --update-pr <number> --entry "<label>" "<url>" [--entry ...]
      Update the ## Screenshots section of a GitHub PR description.

"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------

def get_repo() -> str:
    """Return the current repo in 'owner/name' format via gh CLI."""
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(
            "Error: could not determine current repo. Make sure `gh` is authenticated (`gh auth status`).",
            file=sys.stderr,
        )
        sys.exit(1)
    return result.stdout.strip()


def branch_exists(repo: str, branch: str) -> bool:
    """Return True if the given branch exists in the repo."""
    result = subprocess.run(
        ["gh", "api", f"/repos/{repo}/branches/{branch}"],
        capture_output=True,
    )
    return result.returncode == 0


def create_pr_assets_branch(repo: str) -> None:
    """Create an orphan 'pr-assets' branch via the GitHub API (no local git needed)."""
    print(f"Creating orphan branch 'pr-assets' in {repo}...")

    readme = (
        b"# PR Assets\n\n"
        b"Screenshots hosted here for PR descriptions. "
        b"**Never merge this branch** — it has no shared history with main/develop.\n"
    )
    readme_b64 = base64.b64encode(readme).decode()

    # 1. Create a blob for the README
    blob = _gh_api("POST", f"/repos/{repo}/git/blobs", {
        "content": readme_b64,
        "encoding": "base64",
    })
    blob_sha = blob["sha"]

    # 2. Create a tree pointing to the blob
    tree = _gh_api("POST", f"/repos/{repo}/git/trees", {
        "tree": [{"path": "README.md", "mode": "100644", "type": "blob", "sha": blob_sha}],
    })
    tree_sha = tree["sha"]

    # 3. Create an orphan commit (no 'parents' key = root commit)
    commit = _gh_api("POST", f"/repos/{repo}/git/commits", {
        "message": "chore: init pr-assets branch for PR screenshots",
        "tree": tree_sha,
    })
    commit_sha = commit["sha"]

    # 4. Create the branch reference
    _gh_api("POST", f"/repos/{repo}/git/refs", {
        "ref": "refs/heads/pr-assets",
        "sha": commit_sha,
    })

    print("Branch 'pr-assets' created successfully.")


def _gh_api(method: str, endpoint: str, payload: dict) -> dict:
    """Call `gh api` with a JSON payload and return the parsed response."""
    result = subprocess.run(
        ["gh", "api", "--method", method, endpoint, "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error: gh api {method} {endpoint} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)



def upload_to_github(filepath: str, repo: str) -> str:
    """
    Upload a file to the pr-assets branch via the GitHub Contents API.

    Generates a unique filename using a short UUID suffix to guarantee
    no collisions with existing files (e.g. screenshot-a1b2c3d4.png).

    Returns the raw.githubusercontent.com URL, which:
    - Serves the file with the correct Content-Type (e.g. image/png)
    - Opens inline in the browser when clicked (no forced download)
    - Preserves full resolution — no compression applied
    """
    stem = Path(filepath).stem
    suffix = Path(filepath).suffix
    short_id = uuid.uuid4().hex[:8]
    filename = f"{stem}-{short_id}{suffix}"

    with open(filepath, "rb") as f:
        content_b64 = base64.b64encode(f.read()).decode()

    payload: dict = {
        "message": f"chore: add PR screenshot {filename}",
        "content": content_b64,
        "branch": "pr-assets",
    }

    _gh_api("PUT", f"/repos/{repo}/contents/{filename}", payload)

    return f"https://raw.githubusercontent.com/{repo}/pr-assets/{filename}"


# ---------------------------------------------------------------------------
# PR update
# ---------------------------------------------------------------------------

SCREENSHOTS_PATTERN = re.compile(
    r"(?im)^##\s+screenshots\b.*?(?=\n##\s|\Z)",
    re.DOTALL,
)


def build_screenshots_section(entries: list[tuple[str, str]]) -> str:
    """Build a ## Screenshots markdown section from a list of (label, url) pairs."""
    lines = ["## Screenshots", ""]
    for label, url in entries:
        lines.append(f"### {label}")
        lines.append(f"![{label}]({url})")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def update_pr(pr_number: str, entries: list[tuple[str, str]]) -> None:
    """Fetch current PR body, replace/append ## Screenshots section, update via gh."""
    result = subprocess.run(
        ["gh", "pr", "view", pr_number, "--json", "body", "-q", ".body"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error: could not fetch PR #{pr_number}: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    current_body = result.stdout.rstrip("\n")
    new_section = build_screenshots_section(entries)

    if SCREENSHOTS_PATTERN.search(current_body):
        new_body = SCREENSHOTS_PATTERN.sub(new_section.rstrip("\n"), current_body)
    else:
        separator = "\n\n" if current_body and not current_body.endswith("\n\n") else ""
        new_body = current_body + separator + new_section

    with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as tmp:
        tmp.write(new_body)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["gh", "pr", "edit", pr_number, "--body-file", tmp_path],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"Error: gh pr edit failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)
    finally:
        os.unlink(tmp_path)

    print(f"PR #{pr_number} description updated with {len(entries)} screenshot(s).")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="GitHub pr-assets upload helper for the pr-screenshots skill.",
    )
    parser.add_argument("filepath", nargs="?", help="Image file to upload.")
    parser.add_argument(
        "--setup",
        action="store_true",
        help="Create the pr-assets orphan branch in the current repo (safe to run multiple times).",
    )
    parser.add_argument("--update-pr", metavar="PR_NUMBER", help="PR number to update.")
    parser.add_argument(
        "--entry",
        nargs=2,
        metavar=("LABEL", "URL"),
        action="append",
        dest="entries",
        help="Label + URL pair (repeatable). Used with --update-pr.",
    )
    args = parser.parse_args()

    # --setup
    if args.setup:
        repo = get_repo()
        if branch_exists(repo, "pr-assets"):
            print(f"Branch 'pr-assets' already exists in {repo}. Nothing to do.")
        else:
            create_pr_assets_branch(repo)
        return

    # --update-pr
    if args.update_pr:
        if not args.entries:
            print("Error: --update-pr requires at least one --entry LABEL URL pair.", file=sys.stderr)
            sys.exit(1)
        update_pr(args.update_pr, [(label, url) for label, url in args.entries])
        return

    # Upload single file
    if not args.filepath:
        parser.print_help()
        sys.exit(1)

    if not os.path.exists(args.filepath):
        print(f"Error: file not found: {args.filepath}", file=sys.stderr)
        sys.exit(1)

    repo = get_repo()

    # Auto-create the branch if it doesn't exist yet
    if not branch_exists(repo, "pr-assets"):
        print(f"Branch 'pr-assets' not found in {repo}. Creating it automatically...")
        create_pr_assets_branch(repo)

    url = upload_to_github(args.filepath, repo)
    print(json.dumps({"url": url}))


if __name__ == "__main__":
    main()
