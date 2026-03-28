---
name: pr-screenshots
description: Capture screenshots or GIF recordings of a new UI feature, upload them losslessly to a GitHub orphan branch (pr-assets), and add a Screenshots section to the current PR description. Supports spotlight effects that highlight specific components with a dark overlay, rounded cutout, and explanatory annotations based on the PR diff. Can temporarily modify source code to force UI states, add selectors, or simulate data for accurate captures — all changes are safely reverted after. Images are served via github.com blob URLs which work for both public and private repos. Use when the user wants to visually document a feature in a pull request — triggered by phrases like "add screenshots to my PR", "document this feature visually", "screenshot the new screens", or "record a GIF of this flow".
disable-model-invocation: true
argument-hint: "[screenshot|gif] [url]"
---

# PR Screenshots Skill

Capture screenshots or GIF recordings of UI features, upload them **losslessly** to a dedicated GitHub orphan branch (`pr-assets`), and update the current PR description with a labeled Screenshots section.

Each screenshot can include a **spotlight effect** that highlights the changed component with a dark overlay, a rounded cutout border, and an annotation box explaining what changed — making PR reviews far more informative.

> **Why orphan branch + github.com blob URLs?**
> - **No compression** — images are stored as-is (PNG/GIF), unlike ImgBB which re-encodes them.
> - **Works for private repos** — uses `github.com/{owner}/{repo}/blob/pr-assets/{file}?raw=true` URLs, which render correctly in PR markdown for any authenticated user. Unlike `raw.githubusercontent.com` URLs, these work because GitHub's markdown renderer can resolve images on the same `github.com` domain using the viewer's session.
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

Check whether the user's message already names specific screens or interactions to capture (e.g. "screenshot the login page and the dashboard"). If yes, use those directly as the capture list and skip to 3d.

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

If the user confirms, proceed to 3d.

### 3c. Ask the user

If the diff analysis still doesn't give enough clarity (e.g. the changes are in shared utilities, logic layers, or the diff is too large to reason about), ask:

> "I couldn't determine the exact screens to document from the diff. Which screens, features, or interactions should be captured? Please list each with a short label (e.g. 'Login screen', 'Dashboard after login', 'Error state')."

Wait for the user's response before continuing.

### 3d. Identify component selectors for spotlight

For each item in the capture list, determine a CSS selector for the target component to spotlight:

1. **Analyze the PR diff** to find which DOM elements were changed — look for component names, CSS class names, IDs, `data-testid` attributes, or unique structural selectors.
2. **Propose a selector** for each item (e.g. `.login-form`, `[data-testid="dashboard-header"]`, `#error-modal`).
3. **If no suitable selector exists**, flag the item as `needsTemporarySelector = true` — it will be handled in Step 4 by temporarily adding a `data-pr-screenshot` attribute to the source code.

> If the user doesn't want the spotlight effect on specific items, they can say "no spotlight" and the screenshot will be captured without the overlay.

### 3e. Generate annotation text

For each item in the capture list, draft a short annotation (1-2 sentences) explaining what changed, based on the PR diff:

- Read the relevant diff hunks for the affected component/file.
- Summarize the visible change concisely (e.g. "Added inline validation errors below each form field" or "New empty state illustration when no data is available").

Present all annotations to the user:
> "Here are the proposed annotations for each screenshot: [list]. Would you like to adjust any?"

### 3f. Identify state and data simulation needs

For each capture, determine if additional setup is needed:

- **State forcing** — Does the screenshot require a specific UI state that isn't currently active? (e.g. error modal, loading spinner, empty state, specific tab selected). Flag as `needsStateForcing = true` with a `stateDescription`.
- **Data simulation** — Does the screenshot need specific data that doesn't exist in the current environment? (e.g. populated table with multiple rows, specific user role, edge case values). Flag as `needsDataSimulation = true` with a `dataDescription`.

If any items need state forcing or data simulation, present the plan to the user:
> "To capture [item], I'll need to temporarily [modify X / inject data Y]. This will be reverted after screenshots. Does this approach work?"

---

The output of Step 3 should be a structured capture list:
```
{label, url, selector, annotationText, needsTemporarySelector, needsStateForcing, stateDescription, needsDataSimulation, dataDescription}
```

## Step 4: Prepare Temporary Code Changes

> **Skip this step entirely** if no items in the capture list need temporary selectors, state forcing, or data simulation.

This step handles all source code modifications needed before capturing screenshots. **Every change made here is reverted in Step 7.**

### 4a. Save current working tree state

First, check for uncommitted changes and stash them to protect the user's work:

```bash
git stash push -m "pr-screenshots-backup" --include-untracked
```

Check if the stash was actually created:
```bash
git stash list | head -1
```

If the output contains `pr-screenshots-backup`, record `stash_created = true`. If the working tree was clean (no stash created), record `stash_created = false` so Step 7 knows not to pop.

### 4b. Add temporary selectors

For items flagged with `needsTemporarySelector`:

1. Identify the component file from the PR diff.
2. Add a `data-pr-screenshot="<label-slug>"` attribute to the target element in the source code.
3. Use the Edit tool — make the minimal change needed (just adding the attribute).
4. Record the file path modified and the selector `[data-pr-screenshot="<label-slug>"]` to use in Step 6.

### 4c. Force UI states

For items flagged with `needsStateForcing`:

1. Analyze the application code to determine how to trigger the desired state.
2. Apply **minimal, targeted** source code changes. Examples:
   - Hardcode a condition to `true` (e.g. `if (true || hasError)` instead of `if (hasError)`)
   - Set an initial state variable (e.g. `const [showModal, setShowModal] = useState(true)`)
   - Override an API response inline
   - Add a temporary `useEffect` that sets the desired state on mount
3. Record all modified files.

### 4d. Simulate data

For items flagged with `needsDataSimulation`:

1. Identify the data source in the application (API mock, hardcoded fixture, state store, context provider).
2. Inject realistic simulated data that will render correctly in the UI. Choose realistic values — not "test123" or "Lorem ipsum", but plausible names, dates, amounts, etc.
3. Record all modified files.

> **User override:** The user can request different example data at any time. If they do, modify the simulated data accordingly and retake the screenshot from Step 6.

### 4e. Verify changes compile and render

After all modifications:

1. Wait 2-3 seconds for hot-reload to recompile.
2. Navigate to the target page in the browser.
3. Verify the page loads correctly and the desired state/data is visible.
4. If compilation fails or the page breaks, **immediately revert** (`git checkout -- .`) and try a different approach.

**Critical rules for this step:**
- Every file modified **must** be tracked so Step 7 can revert it.
- Never modify files unrelated to the screenshot capture.
- Prefer the smallest possible change that achieves the desired state.

## Step 5: Choose Capture Mode & Viewport

### 5a. Screenshot vs GIF mode

Parse the `argument` to detect mode:
- If `argument` contains `gif` → **GIF mode**
- Otherwise → **Screenshot mode** (default)

### 5b. Determine mobile captures

**Default: desktop only.** Do NOT ask the user whether they want mobile screenshots — this avoids ambiguity when the user confirms the capture list with "yes" or "ok".

Instead, when presenting the capture plan (Step 3b), include a brief note:
> "Tip: you can also request **mobile screenshots** (390×844) by mentioning 'mobile' at any point."

Only capture mobile screenshots if the user **explicitly** mentions it (e.g. "also mobile", "include mobile", "mobile too", "mobile screenshots"). Possible modes:
- **User mentions "mobile" + desktop context** → capture desktop first, then mobile for each item.
- **User says "only mobile"** → skip desktop, capture only in mobile mode.
- **No mention of mobile** → capture desktop only (default).

Store the result as `capture_modes` (e.g. `["desktop"]`, `["mobile"]`, or `["desktop", "mobile"]`).

### 5c. Set browser resolution before each capture

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

## Step 6: Capture with Spotlight

For each item in the capture list, and for each mode in `capture_modes`:

### 6a. Prepare the page

1. Set the browser resolution (Step 5c).
2. If a URL was provided for this item, navigate to it using `browser_navigate`.
3. Ask the user to navigate to the correct screen if needed.
4. Wait for the page to fully load.

### 6b. Inject spotlight overlay

Read the spotlight script:
```bash
cat ~/.claude/skills/pr-screenshots/scripts/spotlight.js
```

Then inject it via `browser_evaluate` by wrapping the script contents and calling the `spotlight()` function with the item's parameters:

```javascript
// Run via browser_evaluate — replace SCRIPT_CONTENTS with the file contents
() => {
  SCRIPT_CONTENTS
  return spotlight({
    selector: '<selector>',
    annotationText: '<annotation text>',
    margin: 16,
    borderRadius: 12,
    overlayOpacity: 0.6,
    position: 'auto'
  });
}
```

### 6c. Handle injection result

Check the return value:

- **`{ error: "Element not found" }`** — The selector didn't match. Try:
  1. A broader or alternative selector.
  2. If the item was flagged for temporary selector, verify the attribute was added correctly.
  3. Ask the user for help identifying the correct element.
- **`{ success: true, warning: "..." }`** — The selector matched multiple elements. Log the warning and verify the first match is the intended one. If not, use a more specific selector.
- **`{ success: true }`** — Proceed to capture.

### 6d. Take screenshot

**Screenshot mode:**
```
browser_take_screenshot → filename: /tmp/pr-screenshot-{n}.png
```
For mobile captures, use: `/tmp/pr-screenshot-{n}-mobile.png`

**GIF mode:**
1. Start recording: `mcp__claude-in-chrome__gif_creator action=start_recording`
2. Take an initial screenshot to capture the first frame.
3. Perform the interaction steps on the page (spotlight stays visible during recording).
4. Take a final screenshot before stopping.
5. Stop recording: `mcp__claude-in-chrome__gif_creator action=stop_recording`
6. Export: `mcp__claude-in-chrome__gif_creator action=export filename=pr-screenshot-{n}.gif download=true`
7. Find the exported file:
   ```bash
   ls -t ~/Downloads/pr-screenshot-*.gif 2>/dev/null | head -1
   ```
   Fall back to:
   ```bash
   ls -t ~/Downloads/recording-*.gif 2>/dev/null | head -1
   ```

### 6e. Remove spotlight overlay

After each screenshot (not GIF — keep spotlight during GIF recording), remove the injected elements:

```javascript
// Run via browser_evaluate
() => {
  document.querySelectorAll('[data-spotlight]').forEach(el => el.remove());
  return { success: true };
}
```

### 6f. Review with user

Show the screenshot to the user and ask:
> "Does this look right? Options: **retake** / **adjust-spotlight** (change margin, selector, position) / **adjust-text** (modify annotation) / **next** / **done**"

- **adjust-spotlight** — Ask what to change (margin, border radius, position, selector), re-inject with new params, and retake.
- **adjust-text** — Ask for the new annotation text, re-inject, and retake.
- **retake** — Take the screenshot again without changes.
- **next** — Move to the next item in the capture list.
- **done** — Stop capturing and proceed to cleanup and upload.

After all captures, proceed to Step 7.

## Step 7: Cleanup Temporary Changes

> **Skip this step** if Step 4 was skipped (no temporary changes were made).

**This step MUST always execute after captures, even if captures failed partway through.** Do not proceed to upload until cleanup is confirmed.

### 7a. Revert all source code modifications

Revert only the files that were modified in Steps 4b–4d. For each tracked file that was modified:
```bash
git checkout -- <file1> <file2> ...
```

If any **new files** were created during Step 4 (e.g. mock data files), remove them individually:
```bash
rm <new-file1> <new-file2> ...
```

**Do NOT run `git clean -fd`** — it would destroy any untracked files the user created outside of this skill's scope.

### 7b. Restore stashed changes

Only if `stash_created = true` in Step 4a:
```bash
git stash pop
```

If `git stash pop` fails due to conflicts:
1. Run `git stash drop` to remove the stash entry.
2. Warn the user: "Your pre-existing changes could not be auto-restored due to conflicts. They are still available — run `git stash apply stash@{0}` to manually restore them."

### 7c. Verify clean state

```bash
git diff --stat
git status
```

Confirm the output matches the pre-Step-4 state. If there are unexpected leftover changes, alert the user immediately.

**Safety rule:** NEVER proceed to Step 8 until this step confirms all temporary changes have been fully reverted. If revert fails, STOP and alert the user.

## Step 8: Upload to GitHub (`pr-assets` branch)

For each captured file (PNG, GIF, WEBP, JPG), run:
```bash
python3 ~/.claude/skills/pr-screenshots/scripts/pr_assets.py <filepath>
```

The script uploads the file **as-is** (no compression, no re-encoding) to the `pr-assets` orphan branch of the current repo via the GitHub Contents API. It prints JSON: `{"url": "https://github.com/{owner}/{repo}/blob/pr-assets/{filename}?raw=true"}`.

The `github.com/blob/...?raw=true` URL:
- Renders correctly in PR markdown for both **public and private** repositories.
- Works because authenticated GitHub users viewing the PR are already logged in on `github.com`, and the image URL is on the same domain — their session carries through.
- Preserves full resolution and quality — no lossy compression.

> **Why not `raw.githubusercontent.com`?** GitHub's markdown renderer proxies external images through its camo CDN. For private repos, the camo proxy cannot authenticate to `raw.githubusercontent.com`, causing images to appear broken. The `github.com/blob/...?raw=true` format avoids this issue.

Collect all `{label, url}` pairs. If any upload fails, report the error and ask the user whether to retry or skip.

## Step 9: Update PR Description

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

### 1. <Label for screenshot 1>
![<label>](<github.com blob url with ?raw=true>)

### 2. <Label for screenshot 1> – Mobile
![<label> – Mobile](<github.com blob url with ?raw=true>)

### 3. <Label for screenshot 2>
![<label>](<github.com blob url with ?raw=true>)
```

When both desktop and mobile captures exist for the same screen, group them together under consecutive headings (desktop first, then mobile). If a `## Screenshots` section already exists, it is replaced entirely with the new content.
