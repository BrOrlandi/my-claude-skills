#!/usr/bin/env python3
"""
imgbb_upload.py — Upload images to ImgBB and update PR descriptions.

Usage:
  imgbb_upload.py <filepath>
      Upload a single image. Prints {"url": "https://i.ibb.co/..."} to stdout.
      API key is read from the skill's config.json or the IMGBB_API_KEY env var.

  imgbb_upload.py --save-api-key <key>
      Save the ImgBB API key to the skill's config.json.

  imgbb_upload.py --update-pr <number> --entry "<label>" "<url>" [--entry ...]
      Update the ## Screenshots section of a GitHub PR description.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# Config lives next to the scripts/ folder, inside the skill directory.
# Resolves symlinks so it always writes to the real file in the repo.
CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.json"

MAX_SIZE_BYTES = 32 * 1024 * 1024  # 32 MB (ImgBB limit)
SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}


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
    existing = load_config()
    existing.update(data)
    CONFIG_PATH.write_text(json.dumps(existing, indent=2))


def get_api_key() -> str | None:
    """Return API key from config file, falling back to env var."""
    key = load_config().get("imgbb_api_key")
    if key:
        return key
    return os.environ.get("IMGBB_API_KEY")


# ---------------------------------------------------------------------------
# Compression helpers (macOS sips — no external deps)
# ---------------------------------------------------------------------------

def compress_image(filepath: str) -> str:
    """Return a path to a compressed copy of the image if needed, else the original."""
    size = os.path.getsize(filepath)
    if size <= MAX_SIZE_BYTES:
        return filepath

    ext = Path(filepath).suffix.lower()

    if ext == ".gif":
        print(
            f"Warning: GIF is {size / 1024 / 1024:.1f} MB (>{MAX_SIZE_BYTES / 1024 / 1024:.0f} MB limit). "
            "Uploading as-is — ImgBB may reject it.",
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
            "ImgBB may reject it.",
            file=sys.stderr,
        )
    return tmp2_path


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

def upload_image(filepath: str, api_key: str) -> str:
    """Upload image to ImgBB and return the hosted image URL (data.display_url)."""
    ext = Path(filepath).suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        print(
            f"Warning: '{ext}' may not be supported by ImgBB. "
            f"Supported formats: {', '.join(sorted(SUPPORTED_EXTENSIONS))}.",
            file=sys.stderr,
        )

    compressed_path = compress_image(filepath)

    result = subprocess.run(
        [
            "curl",
            "-s",
            "-X", "POST",
            f"https://api.imgbb.com/1/upload?key={api_key}",
            "-F", f"image=@{compressed_path}",
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
        print(f"Error: unexpected response from ImgBB: {result.stdout}", file=sys.stderr)
        sys.exit(1)

    if not response.get("success"):
        error = response.get("error", {})
        message = error.get("message", str(error)) if isinstance(error, dict) else str(error)
        print(f"Error: ImgBB upload failed: {message}", file=sys.stderr)
        sys.exit(1)

    url = response["data"]["display_url"]
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
    parser = argparse.ArgumentParser(description="ImgBB upload helper for pr-screenshots skill.")

    parser.add_argument("filepath", nargs="?", help="Image file to upload.")
    parser.add_argument("--save-api-key", metavar="KEY", help="Save ImgBB API key to skill config.")
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

    # --save-api-key
    if args.save_api_key:
        save_config({"imgbb_api_key": args.save_api_key})
        print(f"API key saved to {CONFIG_PATH}")
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

    api_key = get_api_key()
    if not api_key:
        print(
            f"Error: no ImgBB API key found.\n"
            f"  Option 1 (save to skill config): python3 {__file__} --save-api-key <your-key>\n"
            f"  Option 2 (env var):               export IMGBB_API_KEY=<your-key>\n"
            f"  Get your free key at: https://api.imgbb.com/",
            file=sys.stderr,
        )
        sys.exit(1)

    url = upload_image(args.filepath, api_key)
    print(json.dumps({"url": url}))


if __name__ == "__main__":
    main()
