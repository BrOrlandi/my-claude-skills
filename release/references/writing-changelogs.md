# Writing changelog entries

Three registers, three readers. Mixing them up is the most common way a changelog stops being
read: a store blurb that explains internals, or a developer changelog that says "melhorias
gerais".

## The three registers

**`detail: full` — the file that explains.** `CHANGELOG.md`, Keep a Changelog. Written for
someone who wants to know what changed and why. A couple of sentences per entry is fine; the
reason a feature exists is often the most useful part. Group under Added / Changed / Removed /
Fixed.

```markdown
## [1.1.0] - 2026-08-19

### Added

- **Wear OS app** — the watch shows the battery of everything the phone can see, plus its own.
  It exists because the watch is the one device the phone genuinely cannot read: it connects over
  BR/EDR only and publishes no GATT battery service. So the direction inverts — the watch reads
  itself and reports to the phone.
```

**`detail: oneline` — the in-app line.** A user skimming "what's new" between two versions of the
app. One sentence, bold title first, no implementation detail.

```
**QR Code do ingresso na tela inicial**: No dia do evento, o QR Code do seu ingresso aparece
direto na tela inicial para facilitar o check-in.
```

**`detail: brief` — the store blurb.** A stranger deciding whether to update or install, under a
hard character limit. Bullets, benefit first, no jargon. Count the characters before writing the
file, not after — Play rejects the upload, and truncating later loses the best line.

```
• Cada widget agora tem os próprios ajustes: escolha quais dispositivos, quais baterias e em
  que ordem.
• App do relógio (Wear OS) com mostrador.
```

## Rules that hold in all three

- **Describe the change from outside.** What someone can now do, or what stopped being broken.
  Component names, routes, tables and hooks belong in the commit, not here.
- **One feature, one entry.** Seven commits building one thing is one entry. Splitting by commit
  makes a release look busy and read as noise.
- **Say what was broken, for fixes.** "Corrige leitura de bateria após o Mac dormir" tells the
  reader whether it was their bug; "corrige bug no Bluetooth" does not.
- **Keep the file's language and its diacritics.** pt-BR means á, é, í, ó, ú, ã, õ, â, ê, ô, ç
  spelled correctly, and capitalized month names: Janeiro, Fevereiro, Março, Abril, Maio, Junho,
  Julho, Agosto, Setembro, Outubro, Novembro, Dezembro. Mixed-language files are worse than either
  language alone.
- **Match the existing file exactly.** Heading depth, date format, bullet style, whether titles
  are bold. A new entry that formats differently from the one above it reads as a mistake.
- **Newest first**, and don't edit past entries except to fix a typo. They are what a previous
  release said.
- **Keep the file's own machinery working.** Keep a Changelog files usually carry link references
  at the bottom (`[1.1.0]: https://github.com/<owner>/<repo>/releases/tag/v1.1.0`) and sometimes an
  `## [Unreleased]` section. A new entry adds its link above the previous one and empties
  Unreleased; skipping that leaves the heading rendering as plain text and the next reader fixing
  it by hand.

## Audience filtering

A `public`, `user` or `store` target must not mention work the manifest's `internalTopics` covers,
or that the user flags as internal — admin tooling, other people's data, unannounced features.
This is not tidiness: an entry describing an admin capability tells every user it exists.

When one file serves several audiences, the manifest names the per-entry flag (`adminOnly`) and
the app filters at render time. Then the classification is the decision:

- user-visible: dashboards, profiles, public pages, notifications, purchase flows;
- admin-only: back-office screens, moderation, sync tooling, audit logs, anything reachable only
  with elevated rights.

When a change is both — an admin action a user perceives — write the user-facing half in the user
entry and leave the mechanics to the admin one.

## Before writing

Skim the entries already in the file. Beyond format, they show how much this project explains, how
long its lines run, and whether it names features the way the UI does. Consistency with the file's
own voice beats any external style guide, including this one.
