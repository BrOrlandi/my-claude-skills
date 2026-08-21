# Discovery: reading a repo's release shape

Setup is mostly reading. This is the per-ecosystem map of where to look, so the proposal you put
in front of the user is drawn from the repo instead of from habit.

## Release units

Signals that a repo holds more than one:

| Signal | Likely units |
|---|---|
| `apps/*` + `packages/*`, `pnpm-workspace.yaml`, `workspaces` in `package.json` | one per deployable app; shared packages ride along |
| a mobile dir (`mobile/`, `android-app/`, `ios/`) next to a web dir | mobile and web release independently |
| `settings.gradle.kts` with several `include(...)` modules | usually one unit; modules that ship separately (`wear`) share the version but need distinct build counters |
| `macos-app/` + `android-app/` | two products sharing a name, not a schedule |
| `functions/`, `backend/`, `api/` deployed by CI on merge | often no version line at all — say so instead of inventing one |

A unit needs its own entry when it can ship without the others. Everything else is a path inside
a unit.

## How much release machinery the repo wants

Read this before proposing anything, because the answer is usually "less than the tooling can do":

| Evidence in the repo | Rung it sits on |
|---|---|
| a version field, no tags, no changelog, deploy on merge | version only |
| `CHANGELOG.md` or `HISTORY.md`, maybe tags | local changelog |
| a changelog screen or page in the app's source | user-facing changelog |
| `gh release list` returns releases, or a release workflow exists | published release |
| `playstore/`, `appstore/`, `fastlane/`, Gradle Play Publisher | store |

A repo one rung up from where it sits is a proposal to confirm, not a gap to fill. `cameras-echo`
is the honest floor: `package.json` version bumped in every commit, documented in CLAUDE.md, shown
in a badge, and nothing else — a changelog there would be a file nobody reads.

## Where the version lives

| Stack | File | Fields |
|---|---|---|
| Node / web / library | `package.json` | `version` |
| Android (Gradle) | `app/build.gradle[.kts]` or a shared `version.properties` | `versionName` (semver), `versionCode` (counter) |
| iOS / macOS (Xcode) | `Info.plist`, `*.xcconfig`, or `project.pbxproj` | `CFBundleShortVersionString` (semver), `CFBundleVersion` (counter) |
| Flutter | `pubspec.yaml` | `version: 1.2.3+45` (semver + counter in one string) |
| Rust | `Cargo.toml` | `package.version` |
| Python | `pyproject.toml`, `__init__.py` | `project.version`, `__version__` |
| Go | git tags only | no file — the tag *is* the version |
| Electron / Tauri | `package.json`, `tauri.conf.json` | `version` |
| Docker / backend | CI-injected tag, `VERSION` file | varies; often the git SHA |

Two things worth checking before writing the manifest:

- **Is the version duplicated?** A gradle file and a `version.properties`, or a plist and an
  `xcconfig`, both carrying it. Propose collapsing to the file the build reads; a release that
  updates one and not the other ships an artifact whose version disagrees with the repo.
- **Which field is a counter?** `versionCode` and `CFBundleVersion` are ordering numbers for the
  store, not semantics. They increment on every upload — including a re-upload of the same
  semantic version — and may never repeat.

## Where the changelog lives (or would)

```bash
find . -maxdepth 3 \( -iname 'CHANGELOG*' -o -iname 'RELEAS*' -o -iname 'HISTORY*' \) \
  -not -path '*/node_modules/*' -not -path '*/build/*'
grep -rniE 'release[-_ ]?notes|changelog|novidades' -l \
  --include='*.ts' --include='*.tsx' --include='*.kt' --include='*.swift' --include='*.vue' . \
  | grep -v node_modules
```

Common shapes:

| Shape | Example | Reader |
|---|---|---|
| `CHANGELOG.md`, Keep a Changelog | `## [1.1.0] - 2026-08-19` + Added/Changed/Fixed | developers, GitHub release body |
| store notes file | `playstore/release-notes.md`, a block per version, ≤500 chars | store visitors |
| in-app screen data | `support-releases.ts` array, `ReleaseNotesScreen.kt` list | app users, filtered by role |
| public web page | a route rendering the same data | anyone |
| GitHub releases only | no file in the repo | developers |

A repo can have several at once, and normally should: the file explains, the store blurb sells,
the in-app line tells a user what changed since they last opened the app.

## Build artifacts and channels

| Kind | Artifact | Usual channels |
|---|---|---|
| `web` | deployed by CI on merge | in-app changelog, sometimes a tag |
| `android` | `.aab` (Play) / `.apk` (direct install) | Play track, GitHub release with a versioned APK |
| `ios` / `macos` | `.ipa`, signed `.app` + zip | App Store / TestFlight, GitHub release |
| `desktop` | `.dmg`, `.exe`, `.AppImage` | GitHub release |
| `library` / `cli` | package tarball | npm / PyPI / crates.io, GitHub release |

Evidence a channel is actually wired up — only these justify putting it in the manifest:

```bash
ls .github/workflows/                 # release / publish workflows
ls fastlane/ 2>/dev/null              # iOS/Android automation
grep -rn 'com.github.triplet.play' --include='*.gradle*' .   # Gradle Play Publisher
ls playstore/ appstore/ 2>/dev/null   # store metadata kept in-repo
grep -n '"publish"\|"private"' package.json
gh release list --limit 5
```

A channel with no pipeline stays out of the manifest. Recording an aspiration makes later runs
attempt something that cannot work.

## Anchor choice

| Repo state | `anchor` |
|---|---|
| tags exist and are consistent | `tag` (with the unit's prefix) |
| no tags, changelog has version headings | `changelog-version` |
| no tags, changelog is organized by date | `changelog-date` |
| neither | `manifest` — record `lastRelease` and write it back each run |

State the chosen anchor to the user. It is the one decision that changes which commits show up
next time, and a wrong one silently drops or repeats entries.
