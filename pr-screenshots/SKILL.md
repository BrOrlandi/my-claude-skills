---
name: pr-screenshots
description: Capture screenshots or GIF recordings of a new UI feature, upload them losslessly to a GitHub orphan branch (pr-assets), and add a Screenshots section to the current PR description. Images are served via raw.githubusercontent.com so they open in a new tab when clicked (no forced download). Use when the user wants to visually document a feature in a pull request — triggered by phrases like "add screenshots to my PR", "document this feature visually", "screenshot the new screens", or "record a GIF of this flow".
disable-model-invocation: true
argument-hint: "[screenshot|gif] [url]"
---

# PR Screenshots Skill

Capture screenshots or GIF recordings of UI features, upload them **losslessly** to a dedicated GitHub orphan branch (`pr-assets`), and update the current PR description with a labeled Screenshots section.

> **Why orphan branch + raw.githubusercontent.com?**
> - **No compression** — images are stored as-is (PNG/GIF), unlike ImgBB which re-encodes them.
> - **No forced download** — `raw.githubusercontent.com` serves images with the correct `Content-Type` so clicking opens them in a new browser tab instead of downloading.
> - **Not in the repo history** — the `pr-assets` branch is orphan (no shared ancestor with `main`/`develop`) and is never merged, so it doesn't bloat `git clone`.

---

## Step 1: Identify the PR

Run:
```bash
gh pr view --json number,title,url
```

If no PR is found, stop and tell the user: "No open PR found for the current branch. Please create a PR first."

Extract `number`, `title`, and `url` from the result.

## Step 2: Ensure the `pr-assets` branch exists

Run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/pr_assets.py --setup
```

This checks whether the `pr-assets` orphan branch exists in the current repo. If it doesn't, it creates one automatically via the GitHub API (no local git operations needed). The branch contains only a README and is never meant to be merged.

If the command fails (e.g. no `gh` auth), stop and tell the user:
> "Could not access GitHub. Make sure `gh` is authenticated (`gh auth status`)."

## Step 3: Plan the Captures

Use the following decision process to determine what screenshots are needed — only escalate to the next level if the current level doesn't give enough clarity:

### 3a. Infer from conversation context

Check whether the user's message already names specific screens or interactions to capture (e.g. "screenshot the login page and the dashboard"). If yes, use those directly as the capture list and skip to Step 4.

### 3b. Analyze the PR diff

If the conversation context doesn't make the captures obvious, fetch the PR diff:

```bash
gh pr diff <number>
```

Read the diff and reason about which UI surfaces are affected:
- Look for changes to routes, page components, views, modals, or templates.
- Look for new or modified CSS/styling that would be visible.
- Look for feature flags, conditional rendering, or new API-driven UI states.

From the diff, propose a concrete capture list. Each item should have:
- **Label** — a short human-readable name (e.g. "Login screen – new layout")
- **Why** — one sentence explaining what changed that warrants a screenshot

Present the proposed list to the user:
> "Based on the PR diff, I suggest capturing these screens: [list]. Does this look right, or would you like to adjust it?"

If the user confirms, proceed to Step 4 with this list.

### 3c. Ask the user

If the diff analysis still doesn't give enough clarity (e.g. the changes are in shared utilities, logic layers, or the diff is too large to reason about), ask:

> "I couldn't determine the exact screens to document from the diff. Which screens, features, or interactions should be captured? Please list each with a short label (e.g. 'Login screen', 'Dashboard after login', 'Error state')."

Wait for the user's response before continuing.

---

Parse the final capture list as `{label, description}` pairs to guide navigation in Step 4.

## Step 4: Choose Capture Mode & Viewport

### 4a. Screenshot vs GIF mode

Parse the `argument` to detect mode:
- If `argument` contains `gif` → **GIF mode**
- Otherwise → **Screenshot mode** (default)

### 4b. Ask about mobile experience

Before starting captures, always ask the user:

> "Would you like to also capture **mobile screenshots** (simulating a phone browser at 390×844)? This is great for documenting responsive layouts and mobile-specific UI changes."

Wait for the user's confirmation. Possible responses:
- **Yes / mobile / both** → capture desktop screenshots first, then mobile screenshots for each item.
- **Only mobile** → skip desktop, capture only in mobile mode.
- **No / desktop only** → capture desktop only (default).

Store the result as `capture_modes` (e.g. `["desktop"]`, `["mobile"]`, or `["desktop", "mobile"]`).

### 4c. Set browser resolution before each capture

**Desktop mode (1920×1080) — always use this resolution for desktop:**
```
browser_resize width=1920 height=1080
```
Then wait 500ms for the layout to reflow before taking the screenshot.

> **Important:** always use 1920×1080 for desktop — never use a smaller viewport. The goal is high-resolution, crisp screenshots.

**Mobile mode (390×844, iPhone 14 logical pixels):**

1. Resize the viewport:
   ```
   browser_resize width=390 height=844
   ```
2. Enable mobile emulation via JavaScript to set a mobile user agent, touch events, and pixel ratio:
   ```javascript
   // Run via browser_evaluate
   Object.defineProperty(navigator, 'userAgent', {
     get: () => 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1'
   });
   ```
3. If using Chrome DevTools Protocol (claude-in-chrome), you can also trigger responsive CSS:
   ```javascript
   document.querySelector('meta[name="viewport"]')?.setAttribute('content', 'width=device-width, initial-scale=1');
   ```
4. Wait 800ms for the page to reflow and responsive CSS to apply.
5. Label mobile screenshots with the suffix ` – Mobile` (e.g. "Login screen – Mobile").

After setting the viewport, reload the page or navigate again if the layout didn't respond to the resize.

---

For each item in the capture list, and for each mode in `capture_modes`:

### Screenshot mode (default)

1. Set the browser resolution (Step 4c above).
2. If a URL was provided in the argument or by the user for this item, navigate to it using `browser_navigate`.
3. Ask the user to navigate to the correct screen if needed.
4. Wait for the page to fully load.
5. Capture using Playwright:
   ```
   browser_take_screenshot → filename: /tmp/pr-screenshot-{n}.png
   ```
   For mobile captures, use: `/tmp/pr-screenshot-{n}-mobile.png`
6. Show the screenshot to the user and ask: "Does this look right? Take another screenshot or proceed? (retake/next/done)"

### GIF mode

1. Set the browser resolution (Step 4c above) before starting.
2. Start recording:
   ```
   mcp__claude-in-chrome__gif_creator action=start_recording
   ```
3. Take an initial screenshot to capture the first frame.
4. Guide the user or perform the interaction steps on the page.
5. Take a final screenshot before stopping.
6. Stop recording:
   ```
   mcp__claude-in-chrome__gif_creator action=stop_recording
   ```
7. Export:
   ```
   mcp__claude-in-chrome__gif_creator action=export filename=pr-screenshot-{n}.gif download=true
   ```
8. Find the exported file:
   ```bash
   ls -t ~/Downloads/pr-screenshot-*.gif 2>/dev/null | head -1
   ```
   Fall back to:
   ```bash
   ls -t ~/Downloads/recording-*.gif 2>/dev/null | head -1
   ```
9. Ask: "Take another or proceed to upload? (another/done)"

After all captures, proceed to upload.

## Step 5: Upload to GitHub (`pr-assets` branch)

For each captured file (PNG, GIF, WEBP, JPG), run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/pr_assets.py <filepath>
```

The script uploads the file **as-is** (no compression, no re-encoding) to the `pr-assets` orphan branch of the current repo via the GitHub Contents API. It prints JSON: `{"url": "https://raw.githubusercontent.com/{owner}/{repo}/pr-assets/{filename}"}`.

The `raw.githubusercontent.com` URL:
- Serves the file with the correct `Content-Type` (e.g. `image/png`) — clicking the image in the PR opens it in a new tab instead of downloading it.
- Preserves full resolution and quality — no lossy compression.
- Works for private repos for authenticated GitHub users (i.e. anyone who can view the PR).

Collect all `{label, url}` pairs. If any upload fails, report the error and ask the user whether to retry or skip.

## Step 6: Update PR Description

Run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/pr_assets.py \
  --update-pr <number> \
  --entry "<label1>" "<url1>" \
  --entry "<label2>" "<url2>" \
  ...
```

The script fetches the current PR body, replaces or appends the `## Screenshots` section with labeled images, and calls `gh pr edit` to update the description.

Then open the PR in the browser:
```bash
gh pr view <number> --web
```

Confirm to the user: "Screenshots have been added to PR #<number>. Opening in browser..."

---

## Screenshots Section Format

The skill adds the following section to the PR description:

```markdown
## Screenshots

### <Label for screenshot 1>
![<label>](<raw.githubusercontent.com url>)

### <Label for screenshot 1> – Mobile
![<label> – Mobile](<raw.githubusercontent.com url>)

### <Label for screenshot 2>
![<label>](<raw.githubusercontent.com url>)
```

When both desktop and mobile captures exist for the same screen, group them together under consecutive headings (desktop first, then mobile). If a `## Screenshots` section already exists, it is replaced entirely with the new content.
