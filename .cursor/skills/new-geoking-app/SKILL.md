---
name: new-geoking-app
description: >-
  Wizard to build a GeoKing Android app from zero: local Gradle project, GitHub
  repo, geoking-ci Actions (debug + Play release), Firebase/Play secrets, listing
  + Console declarations, and first internal-track publish. Use when the user
  wants a new app from scratch, greenfield GeoKing project, zero-to-Play Store,
  bootstrap with full CI/CD, or mentions new-geoking-app / new GeoKing app.
---

# New GeoKing app (zero → Play)

Guided wizard. Success = **GitHub Actions green** and an **installable internal
Play track** (production draft is enough for first ship unless the user asks for
public production).

Canonical docs (read when stuck, do not paste wholesale):

| Doc | Role |
|---|---|
| `geoking-tools/INTEGRATION.md` | scripts, Gradle, secrets, workflows |
| `geoking-tools/playstore-listing/` | listing CLI + `play_console.py` |
| Sibling skill `gk-ci` | wiring CI into an **existing** repo |
| Reference apps | **vincent** (KMP model), **arthur** (phone + first-publish answers) |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. Layout:

```
~/dev/android/
├── geoking-tools/
├── geoking-ci/          # must be public on GitHub
└── <new-app>/
```

## Progress checklist (copy & update)

```
- [ ] 0. Intake (name, package, form-factor, GitHub owner)
- [ ] 1. Scaffold Android project + git
- [ ] 2. Bootstrap geoking-tools + geoking-ci callers
- [ ] 3. Create GitHub repo + push main
- [ ] 4. Firebase + google-services + WEB_CLIENT_ID
- [ ] 5. Keystore + Play SA + GitHub secrets (setup-release.sh)
- [ ] 6. Play Console app + fill project.manifest + playConsole
- [ ] 7. Listing assets + data_safety.csv
- [ ] 8. Push main → android-ci + release-play (internal)
- [ ] 9. Internal testers + opt-in install verified
- [ ] 10. (Optional) production draft / send for review
```

Ask only what you need; do not invent package names or Play IDs.

---

## Phase 0 — Intake

Collect (or confirm defaults):

| Field | Default / rule |
|---|---|
| Display name | Title Case, e.g. `MyApp` |
| Package | `fr.geoking.<slug>` (slug = lowercase name) |
| Repo name | same as slug |
| GitHub owner | `ludoo0d0a` (or ask) |
| Form factor | phone-only **or** KMP (phone + wear) |
| Gradle module | `:androidApp` (Arthur-style) or `:composeApp` (Vincent-style) |
| Website | `https://<slug>.geoking.fr` (optional Cloudflare Pages later) |
| First ship bar | **internal completed** + production **draft** (default) |

Refuse to continue without package + name.

---

## Phase 1 — Scaffold the Android project

If the folder does not exist yet, create it under `~/dev/android/<slug>/`.

**Preferred:** agent-generated minimal Compose app matching GeoKing conventions:

- JDK **21** (`jvmToolchain(21)`, `compileOptions` 21, `gradle-daemon-jvm.properties` toolchain 21)
- AGP / Kotlin / Compose versions aligned with **vincent** or **arthur** (copy version catalog when unsure)
- Module path matches intake (`androidApp` or `composeApp`)
- `applicationId` = package
- Empty/minimal UI that **compiles** (`./gradlew :<module>:assembleDebug`)
- Root `settings.gradle.kts`, Gradle wrapper present

**Alternative:** user already created the project in Android Studio → skip generation; verify it builds.

Then `git init -b main` if needed. Ensure `.gitignore` will cover secrets (bootstrap adds GeoKing entries next).

---

## Phase 2 — Bootstrap GeoKing stack

From the **app root**:

```bash
../geoking-tools/templates/bootstrap-new-app.sh --package fr.geoking.<slug> --name <Name>
```

Expect: `scripts/` wrappers, `project.manifest.json` (+ `playConsole` fragment),  
`.github/workflows/{android-ci,release-play}.yml`, optional Cloudflare Pages templates,  
`playstore/version.properties` + `whatsnew.xml`, `.gitignore` updates.

Agent must then:

1. Set `build.gradleModule` / `googleServices` / `mainActivity` in the manifest to match the scaffold.
2. Patch `release-play.yml` `package_name` and `android-ci.yml` `artifact_name`.
3. If module ≠ `:composeApp`, set workflow `gradle_module`, `apk_glob`, `aab_glob` (see INTEGRATION.md).
4. Apply Gradle signing + `VERSION_CODE`/`VERSION_NAME` + BuildConfig secrets from **gk-ci** / INTEGRATION §4 (env-based keystore; never commit `.keystore`).
5. Add thin wrappers if missing: `scripts/listing-cli.sh`, `scripts/play-console.sh` → `$GK_TOOLS/playstore-listing/…`.

---

## Phase 3 — GitHub repo + CI prerequisites

```bash
gh auth status
gh repo create <owner>/<slug> --private --source=. --remote=origin --push
```

(Use `--public` only if the user asks.)

Confirm **geoking-ci** is public on GitHub (`ludoo0d0a/geoking-ci`). Without it, `workflow_call` fails on Free plans.

Do **not** expect the first Actions run to publish until secrets exist (phase 5).

---

## Phase 4 — Firebase

1. Create Firebase/GCP project (or reuse) with Android app = package.
2. Put IDs into `scripts/project.manifest.json` (`project.id`, `firebaseAndroidAppId`, `urls.firebase.*`).
3. `firebase login` then:

```bash
./scripts/pull-google-services.sh --push
```

Never hand-edit `google-services.json`. OAuth needs **both** Android (type 1 + SHA-1) and Web (type 3 = `WEB_CLIENT_ID`).

---

## Phase 5 — Secrets wizard

```bash
./scripts/setup-release.sh          # keystore, Play SA, firebase, oauth, verify
./scripts/show-secrets.sh --redact  # confirm GitHub secrets present
```

Required GitHub secrets: `KEYSTORE_*`, `PLAY_SERVICE_ACCOUNT_JSON`,  
`GOOGLE_SERVICES_JSON`, `WEB_CLIENT_ID` (+ `GEMINI_API_KEY` if used).

Play SA permissions: testing tracks + (for listing) store presence — see  
`playstore-listing/service-account-permissions.md`.

---

## Phase 6 — Play Console shell + manifest

1. Create the app in Play Console (default language, app type).
2. Copy `developerId` + `appId` into `urls.play.*` (dashboard / listing / publishing URLs).
3. Fill `playConsole` (contact, category, declarations). Template:  
   `templates/play-console.fragment.json`. Filled reference: **arthur**  
   `scripts/project.manifest.json`.
4. Validate:

```bash
python3 "$GK_TOOLS/playstore-listing/play_console.py" validate
python3 "$GK_TOOLS/playstore-listing/play_console.py" checklist
```

Console UI still required for IARC, some declarations, and ads-ID purpose checkboxes when the APK merges `AD_ID` (Firebase Analytics → usually **Yes + Analytics**).

---

## Phase 7 — Store listing + data safety

1. English source: `scripts/playstore/listing_copy.py` + `doc/playstore/text-en.md`.
2. Screenshots per `doc/playstore/screenshot-guidelines.md` (phone and/or Wear).
3. Generate / validate / upload listing:

```bash
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" generate
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" validate
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" upload --draft
```

4. Data safety CSV at path in `playConsole.declarations.dataSafety.csv`  
   (Arthur: `scripts/playstore/data_safety.csv`). Optional API:

```bash
python3 "$GK_TOOLS/playstore-listing/play_console.py" apply-data-safety
```

---

## Phase 8 — First CI publish (internal)

1. Commit + push `main`.
2. Watch Actions: `android-ci` (debug APK) + `release-play` (AAB → **internal**, status completed).
3. `versionCode` = `github.run_number`; bump locally only when needed; never reuse a code Play already has.
4. If upload fails with duplicate versionCode, bump via empty commit or `workflow_dispatch` after fixing versioning — do not force-overwrite.

Verify track via Play API or Console: internal release **completed**.

---

## Phase 9 — Internal install proof

1. Create testers list; assign to internal track.
2. Share opt-in URL; install on a listed Google account.
3. Record list name + opt-in URL under `playConsole.distribution.internalTesting`.

**Default done criteria:** internal install works. Production may stay **draft**.

---

## Phase 10 — Production (only if asked)

- Keep production **draft** until listings/declarations are complete.
- Send for review from Publishing overview when the user wants public.
- Do **not** mark the wizard complete for “public Play” until the store listing is installable without opt-in.

---

## Agent rules

- Prefer `bootstrap-new-app.sh` + `setup-release.sh` over reinventing scripts.
- Never commit keystores, `google-services.json`, Play SA JSON, or `.keystore-credentials`.
- Never skip `geoking-ci` public check before debugging “workflow not found”.
- Phone-only apps: `build.playStore.requireWearScreenshots: false`.
- FGS / ads-ID: declare only what the shipped APK actually uses (Arthur dropped unused mediaPlayback FGS).
- When integrating CI only (repo already exists), switch to the **gk-ci** skill.

## Additional resources

- [checklist.md](checklist.md) — one-page operator checklist
- [play-first-publish.md](play-first-publish.md) — Console first-publish order + pitfalls
- `geoking-tools/INTEGRATION.md`
- `~/.cursor/skills/gk-ci/SKILL.md` (or project copy) for Gradle snippets
