# Channel: app stores

Store uploads are the least reversible step in a release and the one with the most rules that only
show up as a rejection. Treat production as public the moment it rolls out.

## Google Play

### Version codes

Play orders uploads by `versionCode`. It must strictly increase and may never repeat — including
for a re-upload of the same `versionName`. Two modules publishing under one `applicationId` (phone
+ Wear OS) cannot share a code, which is why the watch takes `versionCode + 1000`: phone 2, watch
1002.

### Track and release status — two separate choices

| User intent | `--track` |
|---|---|
| produção / público / loja / "pra todo mundo" | `production` |
| teste interno / convidados (até 100) | `internal` |
| teste fechado / closed beta | `alpha` |
| teste aberto / open beta | `beta` |

| `--release-status` | Effect |
|---|---|
| `draft` | Uploads without rolling out. A human reviews and clicks rollout in the console. |
| `completed` | Rolls out to that track's users immediately. |

**Production defaults to `draft`.** A completed production release is public and hard to walk
back, so state what you are about to do and get an explicit yes before `completed` on production.
On testing tracks `completed` only reaches invited or opted-in testers and is a fine default.

### Upload

With Gradle Play Publisher wired into the project:

```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
  ./gradlew publishReleaseBundle --track internal --release-status completed
```

Play requires an `.aab`, not an `.apk`, and the bundle must be signed with the upload key the app
was registered with. Read the tail of the output for `BUILD SUCCESSFUL` and the
`Updating ... release (...:N) in track '...'` line — that N is the version code that landed.

Notes come from `src/main/play/release-notes/<lang>/<track>.txt` when GPP is configured that way;
otherwise from the console. **500 characters per language, hard limit.**

### Promoting instead of uploading twice

Ship to `internal` first, let the team try it, then promote that same build to production in the
console. The artifact users get is the one that was validated, and the version history stays
clean. One trap: a promoted build inherits the internal release's notes, so replace them with real
user-facing text before rolling out — otherwise the store shows "primeira versão de teste
interno" to everyone. Discard any stale production draft first, or you end up with two competing
drafts.

### Failures worth recognizing

| Symptom | Cause |
|---|---|
| `Version code N has already been used` | the counter didn't move, or that code was uploaded before. Bump higher and rerun. |
| `403` / "caller does not have permission" | the service account lacks the release permission on the app, or the grant hasn't propagated yet. |
| unsigned / signature mismatch | wrong keystore or missing `keystore.properties`. Phone and watch must share the signature. |
| rejected target API level | Play raises the minimum `targetSdkVersion` yearly; raising it never drops older devices, `minSdkVersion` does. |

Console-only tasks — tester lists, opt-in links, prices, sales — have no API. When one is needed,
walk the user through the console rather than pretending it can be automated.

## App Store / TestFlight

- `CFBundleShortVersionString` is the semantic version users see; `CFBundleVersion` is the build
  counter, which must increase for every upload of the same version.
- TestFlight distribution is the analogue of an internal track: fast, no App Review for internal
  testers, and the natural place to validate the exact build that will be submitted.
- App Review is a queue with a human at the end. Submitting is not shipping — a rejection costs
  days, so the "what's new" text and the screenshots matter as much as the binary.
- Release can be automatic on approval or manual. Manual is the safer default: it puts the moment
  the release becomes public in the user's hands.

## Always

Report the version name and every counter uploaded, the track and status used, and the exact
console step that remains for the user. The final rollout click is theirs — it is the publish
action, and automating someone else's decision to go public is not a favor.
