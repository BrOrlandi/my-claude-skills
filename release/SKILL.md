---
name: release
description: >-
  Establish and then run a repository's release convention: semantic version bump, changelog
  and release notes written from the commits since the last release, git tag, GitHub release
  with versioned assets, in-app or public changelog screens, and app store notes. The first
  time it runs in a repo it detects the stack (web app, Android, iOS, macOS/desktop binary,
  library/CLI, or a monorepo holding several apps), agrees the convention with the user, and
  records it in `.claude/release.json` plus a short CLAUDE.md section — so every later run,
  and any agent working without this skill, knows where the version lives, which changelog
  to update, and how the release is published. Use this skill whenever the user mentions
  release notes, changelog, novidades, semantic versioning, "fechar uma versão", "nova
  versão", "subir a versão", "bump", tags, GitHub releases, publishing a build to a store, or
  asks what changed since the last release. Also offer it proactively right after a PR is
  created or merged and after finishing a user-facing feature, when the repo has a release
  convention configured — and use it to set one up for a project that has none.
argument-hint: "[setup|notes|publish] [app]"
---

# Release

One skill with two jobs: work out how *this* repository releases and write that down, then
run it.

Release mechanics differ per repo and per app inside a repo — where the version number lives,
which file the changelog is in, who reads it, how the build reaches users. Re-deriving that
from scratch on every release is how you get a version bumped in the wrong file, a duplicated
changelog entry, or a store build that still carries last week's version. Deciding it once
and recording it turns each later release into a mechanical run that can be checked.

The recorded convention lives in two places on purpose:

- `.claude/release.json` — the structured facts this skill reads (apps, version files,
  changelog targets, publish channels, audiences, languages).
- A `## Release & Changelog` section in the repo's `CLAUDE.md` — the same facts in prose, so a
  session that never triggers this skill still bumps the right file and tags correctly.

## Choosing the mode

| Situation | Mode |
|---|---|
| `.claude/release.json` missing, or it doesn't cover the app being released | **setup** |
| Manifest covers the app; user wants entries written and the version bumped | **notes** |
| Version bumped and changelog written; artifacts and channels remain | **publish** |
| User just says "release" / "fechar uma versão" | **notes**, then offer **publish** |

An explicit first argument (`setup`, `notes`, `publish`) overrides the table. A second argument
names the app id from the manifest when the repo has more than one.

Run setup silently-first: read the manifest before asking anything. A repo that already has a
convention should never be interviewed again.

## Mode: setup

The goal is a manifest that is true, not a manifest that is complete. Record what the repo
actually does today; leave channels the repo has no pipeline for out of it.

### 0. Settle the scope — most of this is optional

Release machinery is a ladder, and plenty of repos stop on the first rung. Each rung is opt-in:

| Rung | What it means | Fits |
|---|---|---|
| 1. **version only** | a version file and a bump policy. No changelog, no tag, no release. | internal tools, homelab services, anything deployed on merge |
| 2. **+ local changelog** | a `CHANGELOG.md` written for whoever reads the repo | libraries, CLIs, apps whose users are developers |
| 3. **+ user-facing changelog** | an in-app "novidades" screen or a public page | products with users who never see the repo |
| 4. **+ published release** | tag, GitHub release, versioned assets | anything people download |
| 5. **+ store** | Play, App Store, TestFlight | mobile apps |

Propose the rung the repo already evidences — a `CHANGELOG.md` puts it at 2, `gh release list`
output at 4, a `playstore/` directory at 5 — and confirm before going higher. A repo whose version
only exists so a badge can show it (`bump.cadence: "per-commit"`, empty `changelogs`, empty
`publish`) is a complete, valid manifest; adding a changelog it never asked for creates a file
nobody maintains. Asking is cheap here and the answer is stable for years.

### 1. Read what is already there

```bash
cat .claude/release.json 2>/dev/null
find . -maxdepth 3 \( -iname 'CHANGELOG*' -o -iname 'RELEAS*' -o -iname 'HISTORY*' \) \
  -not -path '*/node_modules/*' -not -path '*/build/*' -not -path '*/.git/*'
git tag --sort=-creatordate | head -20
ls .github/workflows/ 2>/dev/null
grep -rn -iE 'release|changelog|version' CLAUDE.md README.md 2>/dev/null | head -30
```

Code-embedded changelogs don't show up in a filename search — a screen inside the app is the
most common target in your repos, so grep for it:

```bash
grep -rniE 'release[-_ ]?notes|changelog|novidades' --include='*.ts' --include='*.tsx' \
  --include='*.kt' --include='*.swift' --include='*.vue' --include='*.py' -l . \
  | grep -v node_modules | head -20
```

`references/discovery.md` has the per-ecosystem table: where each stack keeps its version, what
its build artifact is, and which release channels it usually has.

### 2. Decide the release units

One release unit = one version line = one entry in `apps`. Split by what ships independently,
not by directory count: a Next.js app plus its shared package is one unit; a macOS app and an
Android app in the same repo are two.

In a multi-unit repo, tags need a per-unit prefix (`v1.1.0` vs `android-v1.1.0`). Without it two
tags called `1.1.0` mean two different things and the history stops being readable. Say this
when proposing the scheme — it is the kind of decision that is cheap now and expensive later.

### 3. Settle each unit with a concrete proposal

Read the repo, form an opinion, then confirm with `AskUserQuestion` showing the proposal and the
alternatives. Open-ended questions waste the user's time when the answer is visible in the repo.
Per unit, settle:

- **version source** — the file(s) and field(s) that are the truth. Prefer the one file the build
  already reads; if the version is duplicated across files, propose collapsing it to one and note
  why (a release that leaves two files disagreeing is a silent bug).
- **anchor** — how "since the last release" is computed: a tag prefix, the top version in a
  changelog, or the date of the top entry. Pick what the repo can actually answer today.
- **bump cadence** — `per-release` (a version per release, the common case) or `per-commit`
  (every commit raises the version, which suits a service whose version is a freshness signal
  rather than a release name).
- **changelog targets** — zero or more, each with audience (`public`, `user`, `admin`, `store`,
  `internal`), language, detail level, and character limit if any. Several per unit is normal: the
  file that explains and the store blurb that sells are different texts for different readers.
  Zero is also normal — see the ladder above.
- **build** — commands and artifact paths, if the unit produces a binary.
- **publish channels** — only the ones wired up (`git-tag`, `github-release`, `in-app`,
  `play-store`, `app-store`). An empty list means the version lives in the repo and nowhere else.
- **docs** — where the human-readable process lives.

### 4. Write `.claude/release.json`

Schema and a worked multi-app example: `references/manifest-schema.md`. Keep the file small and
literal — paths relative to the repo root, no invented fields.

### 5. Write the CLAUDE.md section

If the repo already documents its versioning rules, write **into that section** — keep its heading
and its wording, and add what is missing (the manifest pointer, the files, the tag scheme). Those
rules were written by someone who knows the project, and a heading the author chose is how they
find it again; replacing it with this skill's preferred title loses that for no gain. Only add a new
`## Release & Changelog` section when there is nothing to extend.

Either way, aim for the shortest text from which someone with no other context can do the release
by hand:

```markdown
## Release & Changelog

Structured convention: `.claude/release.json` (read by the `release` skill). Process: `RELEASING.md`.

- **android-app/** — version in `android-app/version.properties` (`versionName` + `versionCode`;
  the watch module publishes at `versionCode + 1000`). Changelog: `android-app/CHANGELOG.md`
  (Keep a Changelog, explains) and `playstore/release-notes.md` (≤500 chars, pt-BR, sells).
  Tag `android-vX.Y.Z`. Publishes both AABs to Play.
- **macos-app/** — version in `macos-app/Resources/Info.plist` (`CFBundleShortVersionString` +
  `CFBundleVersion`, same value). Changelog: `CHANGELOG.md`. Tag `vX.Y.Z`. GitHub release with
  the signed zip.

Bump from conventional commits (breaking → major, `feat` → minor, otherwise patch), confirmed
with the user. Build counters (`versionCode`, `CFBundleVersion`) only ever increase.
```

### 6. Write or extend the human doc

If the flow has manual steps (store consoles, signing, checklists), a `RELEASING.md` earns its
place. Keep the manifest as the source of truth for paths and let the doc carry commands,
rationale, and a per-unit checklist — duplicating paths in both is how they drift apart.

### 7. Create what is missing, with approval

Rungs 2 and 3 may need a file or a screen that doesn't exist yet. Propose it, name what it
costs to maintain, and create it only once the user agrees — never as a side effect of setup:

- a `CHANGELOG.md` in Keep a Changelog format, seeded with the current version;
- an in-app changelog screen or public page — see `references/channel-in-app-changelog.md`.

Seed history from tags and commits, and say plainly which parts were inferred. Inventing past
releases makes the file untrustworthy for every future reader.

### 8. Dry-run before declaring setup done

Run notes mode read-only (step 2 below, without writing) and show what the next release would
look like. A manifest that produces a sensible range and version proposal is verified; one that
was only written is not.

## Mode: notes

### 1. Load the manifest and pick the unit

If the manifest is missing, or the commits at hand touch an app it doesn't cover, switch to setup
for that unit first.

Two shapes skip most of what follows:

- **No changelog targets** (rung 1): the run is a version bump and a commit. Steps 3 and 5 don't
  apply — there is nowhere to write an entry, and inventing a changelog file mid-release is a
  decision for setup, not for a release.
- **`bump.cadence: "per-commit"`**: the bump rides along with the change it describes, staged in
  the same commit rather than as a release of its own. The version answers "how fresh is what I'm
  looking at", so it moves whenever the code does.

### 2. Collect the changes

```bash
python3 ~/.claude/skills/release/scripts/collect_changes.py --app <id>
```

It resolves the anchor, lists the commits scoped to the unit's paths, marks breaking changes,
reads the current version, and proposes the next one. Add `--json` when you want the raw data.
If the repo's layout defeats it, the script's header documents the equivalent git commands — fall
back to those rather than guessing a range.

### 3. Decide what earns an entry

| Earns an entry | Stays out |
|---|---|
| `feat` that changes what a user or admin can do | `docs`, `chore`, `test`, `ci`, `style` |
| `fix` for a bug someone could have hit | internal refactors with no behavior change |
| behavior changes hidden under `refactor:` | infra, tooling, dependency bumps |
| performance a user would notice | work already shipped in an earlier entry |

Group related commits into one entry. Seven commits that build one feature are one line to the
reader — the changelog is a record of changes to the product, not to the tree.

When a subject is vague (`fix: adjust widget`), read the change before writing about it:

```bash
git show --stat <sha>
```

An entry that misdescribes what shipped costs more trust than a missing entry.

### 4. Propose the version

Default policy is conventional commits: any breaking change → major, any `feat` → minor,
otherwise patch. Show the current version, the proposal, and the grouped commit list, and
confirm — the bump is a product decision (a `feat` the user considers a fix, a 0.x line where
minor means something else) that the commits alone can't settle.

Build counters are separate: `versionCode`, `CFBundleVersion` and friends increment on every
upload and never repeat, independent of the semantic version.

### 5. Write the entries

Follow the shape of the file you are editing, one target at a time, newest first.
`references/writing-changelogs.md` covers the three registers (explaining file, in-app line,
store blurb), language and diacritics, and the traps — leaking admin-only or internal features
into a public target, and technical description where user-facing impact belongs.

Honor `audience` from the manifest. A target marked `public` never mentions a feature the
manifest or the user flags as internal, even when it is the biggest change in the release.

### 6. Bump the version files

```bash
python3 ~/.claude/skills/release/scripts/bump_version.py --app <id> --version X.Y.Z
git diff
```

Read the diff before moving on: version files are small and a wrong edit here is the one mistake
that survives into every artifact.

### 7. Check it still builds

If the changelog target is code (a TS array, a Kotlin list, a Swift struct), run the cheapest
compile or build the repo has. A syntax error in the changelog file is trivial to fix now and
embarrassing after the tag exists.

### 8. Commit

Stage only the files this run touched — never `git add -A`, and never machine-local files that
happen to be dirty (`.claude/settings.local.json` is the usual one; it holds one person's
permissions and means nothing to anyone else). Follow the repo's convention;
`chore(release): <app> vX.Y.Z` is a good default when there is none. Say in the body what the
release contains and why the version moved the way it did.

When the changelog covers a feature that is being committed in the same run, the entry, the bump
and the feature belong in one commit — the history then shows one change, described once.

## Mode: publish

### 1. Check the preconditions

Working tree clean, a changelog entry exists for the version being published, and the version
files say that same version. Publishing a version nobody wrote notes for produces a release with
an empty body, which defeats the point.

For anything people install — an app, a binary, a store build — the user should have run this
build and seen it work before it goes out. Ask whether they have; if they haven't, offer the local
install command from the repo's docs and wait. A release is the wrong place to discover that the
artifact doesn't launch.

### 2. Build and verify the artifact carries the version

Run the unit's build commands, then confirm the built artifact reports the new version — not the
source file, the artifact:

```bash
# Android AAB
unzip -p app-release.aab base/manifest/AndroidManifest.xml | strings | grep -A1 versionName
# macOS app bundle
defaults read "$PWD/build/My App.app/Contents/Info" CFBundleShortVersionString
# npm package
node -p "require('./package.json').version"
```

One command rules out the most annoying failure in this whole flow: a correctly tagged release
whose binary is the previous version.

### 3. Tag

Use the unit's prefix, annotated when configured, then push. Never move or delete a tag that has
been pushed to fix a mistake — someone may already have it. Ship the next patch instead.

### 4. Run the channels

One reference per channel, read the one you need:

- `references/channel-github-release.md` — tag, release body from the changelog entry, versioned
  assets, retrying a half-finished release.
- `references/channel-in-app-changelog.md` — changelog screens and public pages: data file
  formats, audience filtering, creating one that doesn't exist yet.
- `references/channel-app-stores.md` — Google Play (tracks, release status, version codes, Wear
  OS, 500-character notes) and App Store / TestFlight.

### 5. Report

Version and counters published, tag name, artifacts uploaded, channel URLs, and exactly what is
left for the user to click. A rollout the user must confirm is not done until they say so — say
which step is theirs.

## Guardrails

Most of this mode's actions are public and awkward to reverse: pushing a tag, creating a GitHub
release, rolling out to a store. Before the first outward action of a run, state what will become
public and get one clear yes; that yes covers the run you described, not the next one.

Store rollouts to production default to a draft the user reviews and rolls out themselves.
Testing tracks reaching invited testers are low-risk and fine to complete directly.

Never delete or overwrite a published tag, release, or store version to correct an error. Never
reuse a build counter. Both leave users on artifacts that no longer match their version.

## Working from the pr skill

After a PR is created or merged, check for `.claude/release.json`. If it exists and the branch's
commits touch a unit with changelog targets, offer the changelog update in one sentence and let
the user decide. If there is no manifest, stay quiet — a repo without a release convention is not
asking for one at PR time. Offer setup only when the user brings it up.

## References

| File | Read it when |
|---|---|
| `references/manifest-schema.md` | Writing or extending `.claude/release.json` |
| `references/discovery.md` | Setup: detecting stacks, version files, artifacts, channels |
| `references/writing-changelogs.md` | Writing any entry, in any target |
| `references/channel-github-release.md` | Tagging and publishing on GitHub |
| `references/channel-in-app-changelog.md` | Changelog screens and public pages |
| `references/channel-app-stores.md` | Google Play, App Store, TestFlight |
