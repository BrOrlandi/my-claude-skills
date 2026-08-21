# Channel: git tag + GitHub release

The release page is the artifact's home for anyone outside the repo: the body is the changelog and
the asset is the thing they install. Both are worth the extra minute.

## 1. Tag

```bash
VERSION=1.1.0
PREFIX=android-v            # from version.tagPrefix; plain "v" in a single-app repo
git tag -a "${PREFIX}${VERSION}" -m "Release ${PREFIX}${VERSION}"
git push origin main --follow-tags
```

The prefix is what keeps a monorepo readable — `v1.1.0` and `android-v1.1.0` are different
products. An annotated tag (`-a`) records who released and when, which a lightweight tag does not.

Verify it arrived, because a release created against a tag that only exists locally behaves
strangely:

```bash
git ls-remote --tags origin | grep "${PREFIX}${VERSION}"
```

## 2. Body from the changelog

The body is the entry you just wrote — not a rewrite of it. Pull the section for this version out
of the changelog target named by `notesFrom` and pass it through a quoted heredoc so accents, em
dashes and line breaks survive:

```bash
gh release create "${PREFIX}${VERSION}" \
  --title "${PREFIX}${VERSION}" \
  --latest \
  --notes "$(cat <<'NOTES'
**19 de Agosto de 2026**

- **Cada widget com os próprios ajustes** — escolha quais dispositivos e em que ordem.
- **App do relógio (Wear OS)** — mostrador com as baterias que você escolher no celular.
NOTES
)" \
  dist/my-app-v1-1-0.apk
```

Notes on the body:

- Don't restate the version — the title already carries it.
- Keep the changelog's own wording. Two texts describing one release drift apart.
- For unsigned or non-store distribution, append the install caveat users hit on first open
  (Gatekeeper right-click → Open, "install from unknown sources", and so on). Support questions
  come from its absence.

## 3. Assets

Name assets so a download outside the page still says what it is:

| version | asset |
|---|---|
| `2.1.1` | `banco-bruno-v2-1-1.apk` |
| `1.5.0` | `BT-Battery-Notifier-1.5.0.zip` |

Copy rather than rename when local tooling expects the unversioned path (`dist/app.apk` for
`adb install`): keep both, upload the versioned one.

macOS `.app` bundles must be zipped — GitHub cannot host a directory, and a zip preserves the
bundle structure and signature:

```bash
cd macos-app/build && zip -qr "My-App-${VERSION}.zip" "My App.app"
```

## 4. When something fails halfway

The steps are independently idempotent, so recover the step that failed instead of restarting:

- **tag pushed, release failed** — rerun `gh release create` only.
- **release exists, asset missing** — `gh release upload "${PREFIX}${VERSION}" <file> --clobber`.
- **body wrong** — `gh release edit "${PREFIX}${VERSION}" --notes-file notes.md`.

Don't delete the tag or force-push to fix a mistake. Someone may already have fetched it, and a
moved tag means two people build different code from the same version. Read the error, fix that
step, and if the artifact itself was wrong, ship the next patch.

## 5. Report back

```bash
gh release view "${PREFIX}${VERSION}" --json url,assets --jq '{url, assets: [.assets[].name]}'
```

Give the user the URL, the asset names, and the tag. If a draft was created rather than published,
say that the publish click is theirs.
