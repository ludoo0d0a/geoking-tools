---
name: gk-project-manifest
description: >-
  Create or update scripts/project.manifest.json for a GeoKing Android app
  (package, GCP/Firebase IDs, Gradle module paths, Play Console URLs,
  playConsole first-publish answers). Use when the user asks to init/create/
  update the project manifest, fill Play/Firebase IDs into the manifest,
  regenerate console URLs, merge playConsole, validate the manifest, or
  mentions project.manifest.json / project-manifest.sh / gk-project-manifest.
---

# Project manifest (create / update)

Success = `scripts/project.manifest.json` exists, matches the app (package,
module, console IDs), has `playConsole` when needed, and `validate` is clean
for required fields (optional Play/Firebase IDs may still warn).

| Resource | Role |
|---|---|
| `./scripts/project-manifest.sh` | **Only** CLI for create/update (after `link-scripts.sh`) |
| `templates/project.manifest.template.json` | Seed for `init` |
| `templates/play-console.fragment.json` | Merged as `playConsole` if missing |
| `INTEGRATION.md` §1 | Field reference |
| Sibling **gk-new-geoking-app** / **gk-ci** | Full app / CI wizards that call this |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-project-manifest/`.

```
<app>/
└── scripts/project.manifest.json   # app-only; never commit secrets here
```

## Progress checklist

```
- [ ] 1. link-scripts (or bootstrap) so ./scripts/project-manifest.sh exists
- [ ] 2. init with --package --name [--module]
- [ ] 3. apply Firebase/GCP + Play IDs when known
- [ ] 4. fill-urls (usually done by apply)
- [ ] 5. playConsole TODOs (category, email, testers…) as available
- [ ] 6. validate
```

Ask for package + display name before `init`. Do **not** invent Play
`developerId` / `appId` or Firebase app IDs — leave placeholders and warn.

---

## 1. Ensure the CLI is linked

From app root:

```bash
../geoking-tools/bin/link-scripts.sh
# or: ./scripts/link-scripts.sh
```

Entrypoint: `./scripts/project-manifest.sh` (also `./scripts/gk project-manifest …`).

---

## 2. Create (`init`)

```bash
./scripts/project-manifest.sh init \
  --package fr.geoking.<slug> \
  --name <Name> \
  --module :composeApp   # or :androidApp
```

Optional: `--project-id`, `--website https://<slug>.geoking.fr`, `--force` (overwrite).

Idempotent: existing file is kept unless `--force`; flags still run `apply`.

Module presets set `gradleModule`, `googleServices`, `unitTestTasks`, `aabGlob`.

---

## 3. Update (`apply` / `set`)

When IDs arrive (Firebase, Play Console):

```bash
./scripts/project-manifest.sh apply \
  --project-id <gcp-id> \
  --firebase-android-app-id '1:…:android:…' \
  --play-developer-id <id> \
  --play-app-id <id> \
  --website https://<slug>.geoking.fr
```

Single field:

```bash
./scripts/project-manifest.sh set .playConsole.contact.email hello@geoking.fr
./scripts/project-manifest.sh set-json .playConsole.storeListing.locales '["en-US","fr-FR"]'
```

`apply` always regenerates `urls.firebase` / `urls.gcp` / `urls.play` from IDs
(`fill-urls`). Re-run `fill-urls` alone after hand-editing IDs.

```bash
./scripts/project-manifest.sh merge-play-console   # if playConsole missing
```

---

## 4. Validate

```bash
./scripts/project-manifest.sh validate
./scripts/project-manifest.sh show
./scripts/project-manifest.sh get .project.package
```

Required for a green validate: `project.package`, `project.name`,
`build.gradleModule`, `build.googleServices`. Play/Firebase IDs and
`playConsole` TODOs are warnings until filled.

---

## Default decisions

| Choice | Default |
|---|---|
| Package | `fr.geoking.<slug>` |
| Module | `:composeApp` (Vincent) or `:androidApp` (Arthur) — ask |
| Website | `https://<last-segment-of-package>.geoking.fr` |
| playConsole | merge fragment; leave TODO until user provides answers |
| Hand-edit JSON | Prefer CLI `set` / `apply` so URLs stay consistent |

---

## Do not

- Duplicate manifest logic in app-local scripts — call `project-manifest.sh`.
- Invent Play / Firebase IDs.
- Commit keystores or raw secrets into the manifest (IDs and public URLs only).
- Confuse with `templates/project.manifest.json` (DNS catalogue) or AndroidManifest.xml.

## Related

- Full greenfield: **gk-new-geoking-app** (phase 2/6 uses this CLI).
- CI wiring only: **gk-ci**.
- First-publish answers deep-dive: `skills/gk-new-geoking-app/play-first-publish.md` + `./scripts/play-console.sh validate`.
