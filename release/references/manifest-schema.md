# `.claude/release.json` schema

The manifest is the structured half of a repo's release convention — paths and formats an agent
can act on without re-deriving them. The prose half lives in the repo's `CLAUDE.md`. Keep both in
sync; when they disagree, the manifest is the one the scripts read.

Every path is relative to the repository root. Omit any key the repo has no answer for — an absent
key is honest, a guessed one causes a wrong edit.

## Top level

```json
{
  "manifestVersion": 1,
  "commitConvention": "conventional",
  "bump": { "policy": "conventional-commits", "confirm": true },
  "apps": [ /* one entry per release unit */ ]
}
```

| Key | Values | Meaning |
|---|---|---|
| `manifestVersion` | `1` | Schema version. |
| `commitConvention` | `conventional` \| `free` | Whether commit subjects can be classified by prefix. With `free`, classification falls back to reading the diffs. |
| `bump.policy` | `conventional-commits` \| `manual` | How the next version is proposed. `manual` always asks. |
| `bump.cadence` | `per-release` \| `per-commit` | `per-release` is the common case. `per-commit` means every commit raises the version and stages it with the change — for a service whose version is a freshness signal rather than a release name. |
| `bump.confirm` | `true` \| `false` | Whether to confirm the version with the user. Default `true`. |

`changelogs` and `publish` are both allowed to be empty. An app with a version file and nothing
else is a complete entry: the repo tracks a version, and no changelog or release channel was ever
wanted. Recording the absence is the point — it stops every later run from re-proposing machinery
the user already declined.

## An app (release unit)

```json
{
  "id": "android",
  "label": "Android app (phone + watch)",
  "kind": "android",
  "paths": ["android-app"],
  "version": {
    "anchor": "tag",
    "tagPrefix": "android-v",
    "annotatedTag": true,
    "files": [
      { "path": "android-app/version.properties", "format": "properties", "key": "versionName", "kind": "semver" },
      { "path": "android-app/version.properties", "format": "properties", "key": "versionCode", "kind": "counter" }
    ]
  },
  "changelogs": [
    { "path": "android-app/CHANGELOG.md", "format": "keep-a-changelog", "audience": "public", "language": "en", "detail": "full" },
    { "path": "playstore/release-notes.md", "format": "md-version-sections", "audience": "store", "language": "pt-BR", "detail": "brief", "maxChars": 500 }
  ],
  "build": [
    { "cmd": "bash build.sh --bundle", "cwd": "android-app", "artifact": "android-app/app/build/outputs/bundle/release/app-release.aab" },
    { "cmd": "bash build.sh --wear --bundle", "cwd": "android-app", "artifact": "android-app/wear/build/outputs/bundle/release/wear-release.aab" }
  ],
  "publish": [
    { "channel": "git-tag" },
    { "channel": "play-store", "track": "internal", "defaultReleaseStatus": "draft", "notesFrom": "playstore/release-notes.md" }
  ],
  "docs": ["RELEASING.md#android-releases"],
  "internalTopics": ["multi-user admin access"]
}
```

| Key | Meaning |
|---|---|
| `id` | Short handle used on the command line (`--app android`). |
| `label` | Human name, used when asking the user which unit to release. |
| `kind` | `web` \| `android` \| `ios` \| `macos` \| `desktop` \| `library` \| `cli` \| `backend`. Selects the discovery and channel defaults. |
| `paths` | Directories whose commits belong to this unit. Used to scope `git log`. Omit in a single-app repo to mean the whole tree. |
| `docs` | Human-readable process docs for this unit, anchors welcome. |
| `internalTopics` | Subjects that must never reach a `public`, `user` or `store` target — admin tooling, unannounced work. The reason lives here so a later session doesn't have to rediscover it. |
| `versionDisplay` | Optional, informational: where a user can see the running version (`{"where": "public/version-badge.js", "how": "tap the climate readout"}`). Worth recording when it exists, since it is how a deploy gets verified; never created by setup unless asked for. |

### `version`

| Key | Meaning |
|---|---|
| `anchor` | How "since the last release" is resolved: `tag` (tags matching `tagPrefix`), `changelog-version` (top version heading of the first changelog), `changelog-date` (top entry's date), `manifest` (the `lastRelease` field below, for repos with neither tags nor parseable changelogs). |
| `tagPrefix` | Prefix for this unit's tags — `v` for a single-app repo, `android-v` / `web-v` when several units share the repo so two `1.1.0` tags can't collide. |
| `annotatedTag` | `true` to create `git tag -a`, which records who tagged and when. |
| `lastRelease` | `{ "version": "1.4.0", "date": "2026-08-14" }`. Only for `anchor: "manifest"`; the skill writes it back after each release. |
| `files[]` | Every place the version is written. All of them get updated together. |

`files[]` entries:

| Key | Values | Notes |
|---|---|---|
| `format` | `properties`, `json`, `plist`, `gradle-kts`, `gradle-groovy`, `toml`, `yaml`, `text`, `regex` | Selects the writer in `scripts/bump_version.py`. |
| `key` | Field name or dotted path (`version`, `versionName`, `CFBundleShortVersionString`, `package.version`) | For `text`, omit. |
| `pattern` | Regex with one capture group around the value | `regex` format only, for files nothing else parses. |
| `kind` | `semver` \| `counter` | `semver` is set to the new version; `counter` increments by one. |
| `offset` | integer | Added to a `counter` for a sibling module that must not share a code (Wear OS at `+1000`). |

### `changelogs`

| Key | Values | Notes |
|---|---|---|
| `path` | file path | Code files are valid targets — an in-app screen usually is one. |
| `format` | `keep-a-changelog`, `md-version-sections`, `md-date-sections`, `ts-array`, `kotlin-list`, `swift-array`, `json-array`, `html`, `other` | With `other`, match the existing file's shape by reading it. |
| `audience` | `public`, `user`, `admin`, `store`, `internal` | Drives what may be mentioned. A file with mixed audiences uses a per-entry flag instead — see `entryFlag`. |
| `entryFlag` | e.g. `adminOnly` | The field an entry carries when one file serves several audiences and the app filters at render time. |
| `language` | BCP-47 tag (`pt-BR`, `en`) | Entries are written in this language, diacritics included. |
| `languages` | list of BCP-47 tags | Use instead of `language` when one file holds the same notes in several languages (a store metadata file with an `en`/`pt-BR`/`es` block each). One entry naming its languages beats three entries repeating the same path. |
| `detail` | `full` \| `brief` \| `oneline` | Register: an explaining file, a store blurb, a single in-app line. |
| `maxChars` | integer | Hard limit per release (Play allows 500 per language). Count before writing, not after. |
| `dateFormat` | e.g. `DD de MMMM de YYYY`, `YYYY-MM-DD` | Match the file; month names follow `language`. |

### `publish`

| `channel` | Extra keys |
|---|---|
| `git-tag` | — (uses `version.tagPrefix` / `annotatedTag`) |
| `github-release` | `notesFrom` (changelog path), `assets` (glob or path list, `{version}` placeholder allowed), `latest` |
| `in-app` | — (the changelog target is the delivery; nothing to upload) |
| `play-store` | `track` (`internal`/`alpha`/`beta`/`production`), `defaultReleaseStatus` (`draft`/`completed`), `notesFrom`, `wearTrack` |
| `app-store` | `lane` (`testflight`/`review`), `notesFrom` |

## Worked example: two units in one repo

```json
{
  "manifestVersion": 1,
  "commitConvention": "conventional",
  "bump": { "policy": "conventional-commits", "confirm": true },
  "apps": [
    {
      "id": "macos",
      "label": "macOS app",
      "kind": "macos",
      "paths": ["macos-app"],
      "version": {
        "anchor": "tag",
        "tagPrefix": "v",
        "files": [
          { "path": "macos-app/Resources/Info.plist", "format": "plist", "key": "CFBundleShortVersionString", "kind": "semver" },
          { "path": "macos-app/Resources/Info.plist", "format": "plist", "key": "CFBundleVersion", "kind": "semver" }
        ]
      },
      "changelogs": [
        { "path": "CHANGELOG.md", "format": "keep-a-changelog", "audience": "public", "language": "en", "detail": "full", "dateFormat": "YYYY-MM-DD" }
      ],
      "build": [{ "cmd": "bash build.sh --release", "cwd": "macos-app", "artifact": "macos-app/build/My App.app" }],
      "publish": [
        { "channel": "git-tag" },
        { "channel": "github-release", "notesFrom": "CHANGELOG.md", "assets": ["macos-app/build/My-App-{version}.zip"], "latest": true }
      ],
      "docs": ["RELEASING.md"]
    },
    {
      "id": "web",
      "label": "Web platform",
      "kind": "web",
      "paths": ["app", "packages", "components"],
      "version": {
        "anchor": "changelog-date",
        "tagPrefix": "web-v",
        "files": [{ "path": "package.json", "format": "json", "key": "version", "kind": "semver" }]
      },
      "changelogs": [
        {
          "path": "packages/shared/src/screens/support-releases.ts",
          "format": "ts-array",
          "audience": "user",
          "entryFlag": "adminOnly",
          "language": "pt-BR",
          "detail": "oneline",
          "dateFormat": "DD de MMMM de YYYY"
        }
      ],
      "publish": [{ "channel": "in-app" }],
      "internalTopics": ["audit log internals"]
    }
  ]
}
```

The two units version independently, tag under different prefixes, write to different targets in
different languages, and publish through different channels — which is the whole reason the
manifest is a list rather than a single object.

## Worked example: version only

A homelab service deployed on merge. No changelog, no tags, no releases — the version exists so a
badge on screen can say how fresh the page is, and it moves on every commit:

```json
{
  "manifestVersion": 1,
  "commitConvention": "conventional",
  "bump": { "policy": "conventional-commits", "cadence": "per-commit", "confirm": false },
  "apps": [
    {
      "id": "monitor",
      "label": "Echo Show monitor",
      "kind": "web",
      "version": {
        "anchor": "manifest",
        "files": [{ "path": "package.json", "format": "json", "key": "version", "kind": "semver" }]
      },
      "changelogs": [],
      "publish": [],
      "versionDisplay": { "where": "public/version-badge.js", "how": "tap the climate readout to show v<version> · <build>" }
    }
  ]
}
```

This manifest is finished, not a draft. Treat the empty lists as answers.
