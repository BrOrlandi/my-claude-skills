# Channel: in-app changelog screens and public pages

Here the changelog is a data file the app renders, so an entry is code: it must compile, and it
must respect whatever filtering the screen does.

## Working with an existing target

1. **Read the file first.** The shape of the newest entry is the spec — field names, date format,
   whether descriptions carry a bold title, how audiences are flagged.
2. **Insert at the top** of the array or list. These screens render in order and readers expect
   the newest first.
3. **Leave existing entries alone**, typos aside. They are what an earlier release said.
4. **Compile.** A missing comma in a TS array or Kotlin list breaks the build, and this file is
   usually the last thing anyone suspects.

### TypeScript array (grouped by date, per-entry audience flag)

```typescript
{
  title: '19 de Agosto de 2026',
  features: [
    {
      description:
        '**QR Code do ingresso na tela inicial**: No dia do evento, o QR Code aparece direto na tela inicial.',
      adminOnly: false,
    },
  ],
},
```

### Kotlin list

```kotlin
ReleaseEntry(
    date = "19 de Agosto de 2026",
    items = listOf(
        "Suporte a múltiplos dispositivos — deslize para ver os outros",
        "Indicador de páginas na tela principal"
    )
),
```

### Swift array

```swift
ReleaseEntry(
    version: "1.1.0",
    date: "19 de Agosto de 2026",
    items: ["Mostrador no relógio", "Ajustes por widget"]
),
```

Whatever the language: the file's existing entries win over these sketches.

## Audience filtering

If the screen filters by role, the flag on each entry decides who sees it — so the flag is a
product decision, not a formality. A change is admin-only when it is reachable only with elevated
rights: back-office screens, moderation, sync tooling, audit logs. Everything a normal account can
notice is user-facing.

If the screen does **not** filter, then nothing admin-only belongs in the file at all. Telling
every user that an admin capability exists is a disclosure, and it can't be walked back once
shipped.

## Creating a target that doesn't exist

Only with the user's approval — this adds UI. Keep it to the smallest thing that works:

1. **A data file** holding the entries, separate from the view, so future releases touch data
   only. This is the file that goes in the manifest.
2. **A minimal screen or route** that renders it in the app's existing style: reuse the app's list
   component, typography and spacing rather than introducing a look of its own.
3. **One reachable entry point** — a "Novidades" / "What's new" row in settings, help or the
   header. A screen nobody can reach is not a channel.
4. **Seed with the current version only**, or with history reconstructed from tags and commits and
   labelled as such. Never invent past releases; a fabricated history makes the whole screen
   untrustworthy.

For a public web page the same split applies — data file plus route — with the extra question of
whether it should be in the sitemap and linked from the footer. Ask; it is a marketing decision as
much as a technical one.

Record the target in `.claude/release.json` as soon as it exists, so the next release writes to it
without rediscovering it.
