---
name: pr-screenshots
description: Capture screenshots or GIF recordings of a new UI feature, upload them to ImgBB, and add a Screenshots section to the current PR description. Use when the user wants to visually document a feature in a pull request — triggered by phrases like "add screenshots to my PR", "document this feature visually", "screenshot the new screens", or "record a GIF of this flow".
disable-model-invocation: true
argument-hint: "[screenshot|gif] [url]"
---

# PR Screenshots Skill

Capture screenshots or GIF recordings of UI features, upload them to ImgBB, and update the current PR description with a labeled Screenshots section.

## Step 1: Identify the PR

Run:
```bash
gh pr view --json number,title,url
```

If no PR is found, stop and tell the user: "No open PR found for the current branch. Please create a PR first."

Extract `number`, `title`, and `url` from the result.

## Step 2: Check ImgBB API Key

Check whether the `IMGBB_API_KEY` environment variable is set:

```bash
echo "${IMGBB_API_KEY:+set}"
```

If it is not set, tell the user:

> "You need an ImgBB API key to upload images. Get your free key at https://api.imgbb.com/ and set it in your shell:
> `export IMGBB_API_KEY=your_key_here`"

Stop and wait for the user to set the variable before continuing.

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

## Step 4: Capture Loop

Parse the `argument` to detect mode:
- If `argument` contains `gif` → **GIF mode**
- Otherwise → **Screenshot mode** (default)

For each item in the user's list:

### Screenshot mode (default)

1. If a URL was provided in the argument or by the user for this item, navigate to it using `browser_navigate`.
2. Ask the user to navigate to the correct screen if needed.
3. Wait for the page to fully load.
4. Capture using Playwright:
   ```
   browser_take_screenshot → filename: /tmp/pr-screenshot-{n}.png
   ```
5. Show the screenshot to the user and ask: "Does this look right? Take another screenshot or proceed? (retake/next/done)"

### GIF mode

1. Start recording:
   ```
   mcp__claude-in-chrome__gif_creator action=start_recording
   ```
2. Take an initial screenshot to capture the first frame.
3. Guide the user or perform the interaction steps on the page.
4. Take a final screenshot before stopping.
5. Stop recording:
   ```
   mcp__claude-in-chrome__gif_creator action=stop_recording
   ```
6. Export:
   ```
   mcp__claude-in-chrome__gif_creator action=export filename=pr-screenshot-{n}.gif download=true
   ```
7. Find the exported file:
   ```bash
   ls -t ~/Downloads/pr-screenshot-*.gif 2>/dev/null | head -1
   ```
   Fall back to:
   ```bash
   ls -t ~/Downloads/recording-*.gif 2>/dev/null | head -1
   ```
8. Ask: "Take another or proceed to upload? (another/done)"

After all captures, proceed to upload.

## Step 5: Upload to ImgBB

For each captured file (JPG, PNG, GIF, BMP, or WEBP), run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/imgbb_upload.py <filepath>
```

The script reads `IMGBB_API_KEY` from the environment, uploads the file, and outputs JSON: `{"url": "https://i.ibb.co/..."}`.

Collect all `{label, url}` pairs. If any upload fails, report the error and ask the user whether to retry or skip.

## Step 6: Update PR Description

Run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/imgbb_upload.py \
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
![<label>](<imgbb-url>)

### <Label for screenshot 2>
![<label>](<imgbb-url>)
```

If a `## Screenshots` section already exists, it is replaced entirely with the new content.
