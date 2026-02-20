#!/usr/bin/env python3
"""
imgur_upload.py — Upload images to Imgur and update PR descriptions.

Usage:
  imgur_upload.py <filepath>
      Upload a single image. Prints {"url": "https://i.imgur.com/..."} to stdout.

  imgur_upload.py --save-client-id <id>
      Persist the Imgur Client ID to ~/.claude/pr-screenshots.json.

  imgur_upload.py --update-pr <number> --entry "<label>" "<url>" [--entry ...]
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
from pathlib import Path

CONFIG_PATH = Path.home() / ".claude" / "pr-screenshots.json"
MAX_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except json.JSONDecodeError:
            return {}
    return {}


def save_config(data: dict) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(data, indent=2))


# ---------------------------------------------------------------------------
# Compression helpers (macOS sips — no external deps)
# ---------------------------------------------------------------------------

def compress_image(filepath: str) -> str:
    """Return a path to a compressed copy of the image if needed, else the original."""
    size = os.path.getsize(filepath)
    if size <= MAX_SIZE_BYTES:
        return filepath

    ext = Path(filepath).suffix.lower()
    # GIFs can't be recompressed with sips the same way; upload as-is with a warning
    if ext == ".gif":
        print(
            f"Warning: GIF is {size / 1024 / 1024:.1f} MB (>{MAX_SIZE_BYTES / 1024 / 1024:.0f} MB). "
            "Uploading as-is — Imgur may reject large GIFs.",
            file=sys.stderr,
        )
        return filepath

    tmp1 = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
    tmp1.close()
    tmp1_path = tmp1.name

    # Step 1: reduce JPEG quality to 70
    result = subprocess.run(
        ["sips", "--setProperty", "formatOptions", "70", filepath, "--out", tmp1_path],
        capture_output=True,
    )
    if result.returncode != 0 or not os.path.exists(tmp1_path):
        print("Warning: sips quality compression failed; uploading original.", file=sys.stderr)
        return filepath

    if os.path.getsize(tmp1_path) <= MAX_SIZE_BYTES:
        return tmp1_path

    # Step 2: scale down to max 1920px on the long edge
    tmp2 = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
    tmp2.close()
    tmp2_path = tmp2.name

    result = subprocess.run(
        ["sips", "--resampleHeightWidthMax", "1920", tmp1_path, "--out", tmp2_path],
        capture_output=True,
    )
    if result.returncode != 0 or not os.path.exists(tmp2_path):
        print("Warning: sips resize failed; uploading quality-compressed version.", file=sys.stderr)
        return tmp1_path

    final_size = os.path.getsize(tmp2_path)
    if final_size > MAX_SIZE_BYTES:
        print(
            f"Warning: image is still {final_size / 1024 / 1024:.1f} MB after compression. "
            "Imgur may reject it.",
            file=sys.stderr,
        )
    return tmp2_path


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

def upload_image(filepath: str, client_id: str) -> str:
    """Upload image to Imgur and return the direct image URL."""
    compressed_path = compress_image(filepath)

    with open(compressed_path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode("utf-8")

    result = subprocess.run(
        [
            "curl",
            "--silent",
            "--request", "POST",
            "--url", "https://api.imgur.com/3/image",
            "--header", f"Authorization: Client-ID {client_id}",
            "--form", f"image={image_data}",
            "--form", "type=base64",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"Error: curl failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"Error: unexpected response from Imgur: {result.stdout}", file=sys.stderr)
        sys.exit(1)

    if not response.get("success"):
        error = response.get("data", {}).get("error", "Unknown error")
        print(f"Error: Imgur upload failed: {error}", file=sys.stderr)
        sys.exit(1)

    url = response["data"]["link"]
    return url


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
    # Fetch current PR body
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

    # Write body to a temp file to avoid shell escaping issues
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
    parser = argparse.ArgumentParser(description="Imgur upload helper for pr-screenshots skill.")

    parser.add_argument("filepath", nargs="?", help="Image file to upload.")
    parser.add_argument("--save-client-id", metavar="CLIENT_ID", help="Persist Imgur Client ID.")
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

    # --save-client-id
    if args.save_client_id:
        cfg = load_config()
        cfg["client_id"] = args.save_client_id
        save_config(cfg)
        print(f"Client ID saved to {CONFIG_PATH}")
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

    cfg = load_config()
    client_id = cfg.get("client_id")
    if not client_id:
        print(
            f"Error: no Imgur Client ID configured. "
            f"Run: python3 {__file__} --save-client-id <your-client-id>",
            file=sys.stderr,
        )
        sys.exit(1)

    url = upload_image(args.filepath, client_id)
    print(json.dumps({"url": url}))


if __name__ == "__main__":
    main()
