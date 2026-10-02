# Intégrer geoking-tools + geoking-ci dans une nouvelle app

Guide pas-à-pas pour brancher release Play, OAuth/Firebase, scripts locaux et CI GitHub Actions sur un projet Android KMP (Compose).

**App from zero (wizard) :** skill [`skills/gk-new-geoking-app`](skills/gk-new-geoking-app/SKILL.md) — scaffold → GitHub → secrets → listing → first **internal** Play upload.  
**Manifest only :** skill [`skills/gk-project-manifest`](skills/gk-project-manifest/SKILL.md) + `./scripts/project-manifest.sh`.  
This document is the detailed reference those skills point to.

**Référence :** [vincent](https://github.com/ludoo0d0a/vincent) est l'app modèle ; [arthur](https://github.com/ludoo0d0a/arthur) pour `playConsole` / first-publish.

### Bootstrap en une commande

Depuis la racine de la nouvelle app :

```bash
../geoking-tools/templates/bootstrap-new-app.sh --package fr.geoking.myapp --name MyApp
```

Puis `./scripts/project-manifest.sh apply …` (IDs Firebase/Play) + `./scripts/setup-release.sh`.
Skill dédié : [`skills/gk-project-manifest`](skills/gk-project-manifest/SKILL.md).
Le reste de ce guide détaille chaque étape manuellement.

---

## Prérequis

| Outil | Usage |
|---|---|
| [geoking-tools](https://github.com/ludoo0d0a/geoking-tools) | Scripts release / adb / build local |
| [geoking-ci](https://github.com/ludoo0d0a/geoking-ci) | Workflows GitHub Actions réutilisables |
| `jq` | Lecture du manifest (`brew install jq`) |
| `gh` | Secrets GitHub (`brew install gh && gh auth login`) |
| JDK 21 | Build Gradle |
| Projet GCP/Firebase + fiche Play Console | IDs pour le manifest |

### Layout recommandé

```
~/dev/android/
├── geoking-tools/      # une seule copie pour toutes les apps
├── geoking-ci/         # publié sur GitHub (ludoo0d0a/geoking-ci)
├── vincent/
└── my-new-app/         # ← ton nouveau projet
```

Alternative : `export GK_TOOLS=~/chemin/vers/geoking-tools` si le clone n'est pas sibling.

---

## Checklist rapide

- [ ] 1. Créer `scripts/` + `project.manifest.json` (`./scripts/project-manifest.sh init`)
- [ ] 2. Copier les wrappers shell + `whatsnew.py` (`link-scripts.sh` / bootstrap)
- [ ] 3. Mettre à jour `.gitignore`
- [ ] 4. Adapter `composeApp/build.gradle.kts` (secrets, signing, version)
- [ ] 5. Ajouter `playstore/version.properties` + `playstore/whatsnew.xml`
- [ ] 6. Ajouter les workflows CI dans `.github/workflows/`
- [ ] 7. Remplir IDs Play/Firebase (`./scripts/project-manifest.sh apply` + `validate`)
- [ ] 8. Lancer `./scripts/setup-release.sh` (wizard secrets + keystore)
- [ ] 9. Pousser `geoking-ci` sur GitHub avant le premier run CI

---

## 1. Manifest projet

Crée `scripts/project.manifest.json` — source de vérité pour package, consoles et build.

CLI dédiée (skill **gk-project-manifest**) :

```bash
../geoking-tools/bin/link-scripts.sh   # une fois
./scripts/project-manifest.sh init --package fr.geoking.myapp --name MyApp --module :composeApp
./scripts/project-manifest.sh apply --project-id myapp-123 --play-developer-id ID --play-app-id ID
./scripts/project-manifest.sh validate
```

Ou copie manuelle du template :

```bash
cp ../geoking-tools/templates/project.manifest.template.json scripts/project.manifest.json
```

### Champs obligatoires

| Section | Champ | Exemple |
|---|---|---|
| `project` | `id` | `myapp-499318` (ID projet GCP/Firebase) |
| `project` | `name` | `MyApp` (affiché dans les scripts) |
| `project` | `package` | `fr.geoking.myapp` |
| `build` | `gradleModule` | `:composeApp` |
| `build` | `googleServices` | `composeApp/google-services.json` |
| `build` | `keystoreAlias` | `key0` |
| `build` | `keystoreDn` | `CN=MyApp, OU=GeoKing, O=GeoKing, L=Paris, C=FR` |
| `build` | `mainActivity` | `.MainActivity` → lance `fr.geoking.myapp/.MainActivity` |
| `build` | `signInLogTag` | `MyAppSignIn` (tag logcat pour debug OAuth) |
| `urls.play` | `developerId`, `appId` | IDs Play Console |
| `urls.*` | liens consoles | Firebase, GCP, Play, Gemini, GitHub secrets |
| `playConsole` | first-publish answers | Category, contact, declarations, data-safety CSV path — see `templates/play-console.fragment.json` |

Les URLs Play suivent le motif :
`https://play.google.com/console/u/0/developers/{developerId}/app/{appId}/app-dashboard`

---

## 2. Scripts partagés — référence unique (comme `includeBuild`)

Les scripts vivent **uniquement** dans **geoking-tools**. Chaque app pointe vers
le même arbre (Gradle `includeBuild` + shell) :

```
$GK_TOOLS → <app>/geoking-tools → ../geoking-tools → ../../geoking-tools
```

### Bootstrap / refresh

```bash
# depuis la racine de l'app
../geoking-tools/bin/link-scripts.sh
```

`link-scripts.sh` crée :

| Chemin | Rôle |
|---|---|
| `geoking-tools` → `../geoking-tools` | Symlink local (**gitignored** — CI checkout réel au même path) |
| `scripts/_geoking-wrapper.sh` | Seul vrai script local |
| `scripts/<cmd>.sh` → wrapper | Symlinks (basename = commande tools) |
| `scripts/gk` | `./scripts/gk --list` / `./scripts/gk setup-release` |

Les fichiers app-only restent locaux : `project.manifest.json` (et tout script
vraiment spécifique à l'app). Listing / Play Console / i18n / version-catalog
passent par `link-scripts.sh` → `bin/{listing-cli,play-console,translate-strings,update-version-catalog}.sh`.

### Structure résultante

```
my-new-app/
├── geoking-tools/              # symlink local (ou checkout CI)
├── scripts/
│   ├── _geoking-wrapper.sh     # résout geoking-tools, délègue
│   ├── gk → _geoking-wrapper.sh
│   ├── setup-release.sh → …    # idem pour chaque bin public
│   ├── project.manifest.json   # config spécifique à l'app
│   └── …
└── settings.gradle.kts         # includeBuild("$gkToolsRoot/android")
```

### Test

```bash
./scripts/gk --list
./scripts/pull-google-services.sh
./scripts/setup-release.sh
```

---

## 3. `.gitignore`

Ajoute dans le `.gitignore` de l'app :

```gitignore
local.properties
composeApp/google-services.json

# Signing — never commit
*.keystore
*.jks
scripts/.keystore-credentials
scripts/.adb-wireless

# Local symlink from link-scripts.sh (CI checks out the real repo here)
/geoking-tools

# Generated Play release notes
playstore/whatsnew/
/secrets/*.json
```

---

## 4. Gradle (`composeApp/build.gradle.kts`)

Le stack GeoKing suppose **JDK 21** (CI, daemon Gradle, toolchain Kotlin).

```kotlin
kotlin {
    jvmToolchain(21)
}

android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}
```

`gradle/gradle-daemon-jvm.properties` : `toolchainVersion=21` (foojay auto-provisionne le JDK du daemon).

### Secrets via `local.properties` / env CI

```kotlin
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
fun secret(key: String) = localProps.getProperty(key) ?: System.getenv(key) ?: ""

android {
    defaultConfig {
        buildConfigField("String", "WEB_CLIENT_ID", "\"${secret("WEB_CLIENT_ID")}\"")
        buildConfigField("String", "GEMINI_API_KEY", "\"${secret("GEMINI_API_KEY")}\"")
        // versionCode / versionName — voir ci-dessous
    }
    buildFeatures { buildConfig = true }
}
```

### Version Play (`playstore/version.properties`)

```kotlin
val versionProps = Properties().apply {
    rootProject.file("playstore/version.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

defaultConfig {
    versionCode = (System.getenv("VERSION_CODE") ?: versionProps.getProperty("versionCode") ?: "1").toInt()
    versionName = (System.getenv("VERSION_NAME")?.takeIf { it.isNotBlank() }
        ?: versionProps.getProperty("versionName") ?: "1.0").removePrefix("v")
}
```

CI injecte `VERSION_CODE=max(github.run_number, playstore/version.properties+1)` via
geoking-ci (`resolve-version-code.sh`). Après un publish local, committer le
`versionCode` bumpé dans `playstore/version.properties` pour que la prochaine CI
reste au-dessus de ce plancher.

### Signing release (env vars, pas de keystore commité)

```kotlin
val keystorePath = System.getenv("KEYSTORE_FILE")
signingConfigs {
    create("release") {
        if (keystorePath != null) {
            storeFile = file(keystorePath)
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
}
buildTypes {
    getByName("release") {
        if (keystorePath != null) signingConfig = signingConfigs.getByName("release")
    }
}
```

### Module Gradle

Si ton module n'est pas `composeApp`, mets à jour `build.gradleModule` dans le manifest **et** les inputs CI (`gradle_module`, `apk_glob`, `aab_glob`).

---

## 5. Dossier `playstore/`

Minimum pour la release CI :

```
playstore/
├── version.properties    # versionCode/versionName locaux
└── whatsnew.xml          # notes de version multilingues
```

**`version.properties`**

```properties
versionCode=1
versionName=1.0.0
```

**`whatsnew.xml`** — le script `whatsnew.py` génère `playstore/whatsnew/whatsnew-<locale>` pour l'upload Play :

```xml
<?xml version="1.0" encoding="utf-8"?>
<releases>
  <release versionCode="1" versionName="1.0.0">
    <locale code="fr-FR">Première version.</locale>
    <locale code="en-US">First release.</locale>
  </release>
</releases>
```

Test local : `python3 scripts/whatsnew.py 1`

---

## 6. GitHub Actions (geoking-ci)

Les workflows de l'app sont des **appels fins** vers
**[geoking-ci](https://github.com/ludoo0d0a/geoking-ci)** (dépôt **public** requis pour
`workflow_call` sur GitHub Free).

### Copie des templates

```bash
cp ../geoking-tools/templates/android-ci.yml .github/workflows/
cp ../geoking-tools/templates/release-play.yml .github/workflows/
```

Édite `artifact_name` et `package_name`.

Chaque app ne contient que ~15 lignes YAML ; la logique build/release vit dans geoking-ci.

### Secrets GitHub (par dépôt app)

| Secret | Rôle |
|---|---|
| `KEYSTORE_BASE64` | Keystore upload, base64 |
| `KEYSTORE_PASSWORD` | Mot de passe keystore |
| `KEY_ALIAS` | Alias clé |
| `KEY_PASSWORD` | Mot de passe clé |
| `PLAY_SERVICE_ACCOUNT_JSON` | JSON compte de service Play API |
| `GOOGLE_SERVICES_JSON` | `google-services.json` encodé base64 |
| `WEB_CLIENT_ID` | Client OAuth **Web** (Firebase Auth) |
| `GEMINI_API_KEY` | Clé Gemini (optionnel selon l'app) |

**Ne pas les saisir à la main** — utilise le wizard :

```bash
./scripts/setup-release.sh          # tout
./scripts/setup-release.sh keystore # étape par étape
./scripts/show-secrets.sh           # récap local vs GitHub
```

### Comportement CI

| Événement | Workflow | Résultat |
|---|---|---|
| Push / PR `main` | `android-ci.yml` | APK debug en artefact |
| Push `main` | `release-play.yml` | AAB → piste **internal** |
| Tag `v*` | `release-play.yml` | `versionName` = nom du tag |
| `workflow_dispatch` | `release-play.yml` | Choix de piste Play |

**allowOneBuildAtOnce / cancelPreviousRunningBuild** — défini dans
[geoking-ci](https://github.com/ludoo0d0a/geoking-ci) (`concurrency` +
`cancel-in-progress: true` sur chaque workflow réutilisable). Les templates
app gardent aussi un `concurrency` côté caller pour annuler tout le workflow
appelant (jobs locaux inclus).

---

## 7. Première release — ordre recommandé

1. **Firebase** — créer le projet, ajouter l'app Android (`package`), puis `firebase login` + `./scripts/pull-google-services.sh` (télécharge `google-services.json` → `composeApp/` et synchronise `WEB_CLIENT_ID`)
2. **Keystore** — `./scripts/setup-release.sh keystore` (ou `gen-keystore.sh --gh`)
3. **Play Console** — créer l'app, noter `developerId` + `appId` dans le manifest
4. **Compte de service** — `./scripts/setup-release.sh play`
5. **OAuth** — `./scripts/setup-release.sh firebase` puis `oauth` ; enregistrer SHA-1 debug + Play App Signing
6. **Vérifier** — `./scripts/setup-release.sh verify`
7. **CI** — push sur `main`, vérifier Actions
8. **Play** — première upload internal via CI, ou `./scripts/build-and-publish.sh` si Actions est indisponible

---

## 7bis. Clients OAuth — Android (type 1) vs Web (type 3)

Le Google Sign-In a besoin des **deux** types de clients OAuth dans le projet Firebase ; mais le **code** n'utilise que le client **Web**.

| `client_type` | Client | Rôle | Lié à | Utilisé dans le code ? |
|---|---|---|---|---|
| `1` | **Android** | Autorise l'app/l'appareil à demander une connexion Google | `package_name` + **SHA-1** | Non — Google reconnaît l'app via sa signature |
| `3` | **Web** (« server client ID ») | Audience du jeton d'identité que Firebase vérifie | rien de physique (ID serveur) | **Oui** — `setServerClientId(...)` / `default_web_client_id` / `WEB_CLIENT_ID` |

- `WEB_CLIENT_ID` (local.properties, BuildConfig, secret CI) = **toujours le client Web (type 3)**, jamais l'Android.
- Enregistre **un client type 1 par empreinte** : SHA-1 debug, SHA-1 upload, et surtout SHA-1 **Play App Signing** (sinon le sign-in casse sur le Play Store alors qu'il marche en debug).
- Panne classique : un `google-services.json` qui ne contient qu'un client type 3 (ou le mauvais) et aucun type 1 → « aucun jeton Google reçu » / `signInWithCredential` échoue. Correctif : `./scripts/pull-google-services.sh` re-télécharge le fichier avec tous les clients + resynchronise `WEB_CLIENT_ID`.

---

## 8. Scripts locaux utiles

| Commande | Quand l'utiliser |
|---|---|
| `./scripts/pull-google-services.sh` | Télécharge `google-services.json` depuis Firebase (CLI) + synchronise `WEB_CLIENT_ID` dans `local.properties`. Ajoute `--push` (ou `GK_PULL_PUSH_SECRET=true`) pour pousser aussi les secrets GitHub `GOOGLE_SERVICES_JSON` + `WEB_CLIENT_ID`. Alias : `setup-release.sh config` |
| `./scripts/deploy-device.sh` | Build + install sur téléphone (USB ou Wi-Fi adb) |
| `./scripts/adb-reconnect.sh -s IP:5555` | Garder adb sans fil actif pendant le dev |
| `./scripts/build-aab.sh` | AAB signé local + vérif empreinte avant upload manuel |
| `./scripts/build-and-publish.sh` | **Fallback hors CI** (crédits Actions épuisés) : tests → AAB → upload Play API (piste `internal` par défaut). Options : `--track`, `--skip-tests`, `--skip-review`, `--dry-run`, `-y` |
| `./scripts/show-secrets.sh --redact` | Partager un état config sans secrets en clair |

---

## 9. Personnalisation avancée

### Module Gradle différent de `:composeApp`

`project.manifest.json` :

```json
"build": { "gradleModule": ":app" }
```

Workflows CI — ajoute dans `with:` :

```yaml
gradle_module: ':app'
apk_glob: 'app/build/outputs/apk/debug/*.apk'
aab_glob: 'app/build/outputs/bundle/release/app-release.aab'
```

### Repo geoking-ci fork / autre org

Dans les workflows app, ajoute :

```yaml
with:
  geoking_ci_repo: 'mon-org/geoking-ci'
  geoking_ci_ref: 'v1.0.0'
```

### Pas de Gemini

Omet l'étape `gemini` du wizard ; le secret CI est optionnel si `build.gradle.kts` ne l'utilise pas.

---

## 10. Dépannage

| Symptôme | Piste |
|---|---|
| `geoking-tools introuvable` | `./scripts/link-scripts.sh`, clone sibling, ou `export GK_TOOLS=…` |
| CI : `workflow not found` | `geoking-ci` doit être **public** (ou Team+ avec accès partagé) |
| CI : `gradle: command not found` | Normal si pas de wrapper — geoking-ci provisionne Gradle 8.13 |
| Google Sign-In échoue en local | SHA-1 debug manquant dans Firebase/GCP → `./scripts/verify-oauth.sh` |
| Sign-In : `aucun jeton Google reçu` / `WEB_CLIENT_ID` obsolète | `google-services.json` périmé → `./scripts/pull-google-services.sh` (re-télécharge + resynchronise `WEB_CLIENT_ID`) |
| Google Sign-In échoue sur Play | SHA-1 **App signing** (pas upload) dans Firebase → Play Console → Intégrité |
| `release-play.yml n'injecte PAS WEB_CLIENT_ID` | Le workflow doit utiliser `geoking-ci` avec `secrets: inherit` |
| AAB rejeté (signature) | `./scripts/build-aab.sh` compare l'empreinte avant upload |
| Actions minutes / crédits épuisés | `./scripts/build-and-publish.sh` (même flux que geoking-ci, upload Play API local) |

---

## Fichiers template

Tous dans `geoking-tools/templates/` :

| Fichier | Destination dans l'app |
|---|---|
| `project.manifest.template.json` | seed pour `bin/project-manifest.sh init` → `scripts/project.manifest.json` |
| `play-console.fragment.json` | merged into `playConsole` via `project-manifest.sh merge-play-console` |
| `_geoking-wrapper.sh` | `scripts/_geoking-wrapper.sh` |
| `script-stub.sh` | legacy — préférer `link-scripts.sh` |
| `whatsnew.py` | `scripts/whatsnew.py` |
| `android-ci.yml` | `.github/workflows/android-ci.yml` |
| `release-play.yml` | `.github/workflows/release-play.yml` |

| Script / skill | Rôle |
|---|---|
| `bin/project-manifest.sh` | Créer / maj / valider le manifest app |
| `skills/gk-project-manifest/` | Skill agent pour le même flux |

---

## 10. Translate + Play listing (shared)

Scora remains the historical reference; **shared copies** live in this repo (do not refactor Scora in place).

**Skill:** [`skills/gk-i18n`](skills/gk-i18n/SKILL.md) — bootstrap `<app>/i18n/` from `translate/`, DeepL forward/back, glossary, roundtrip.

| Path | Role |
|---|---|
| `translate/` | DeepL app-string pipeline (`translate.sh`, `translate.py`, …) |
| `skills/gk-i18n/` | Agent skill for wiring the Scora-style `i18n/` tree |
| `playstore-listing/` | Play listing CLI, listing translate, screenshot validation |

Play Console **service account permissions** (listing + release tracks):  
[`playstore-listing/service-account-permissions.md`](playstore-listing/service-account-permissions.md)

From an app (sibling of `geoking-tools`):

```bash
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"

# App strings (adapt modules/languages in your scripts/ wrappers)
"$GK_TOOLS/translate/translate.sh"

# Play listings
pip install -r "$GK_TOOLS/playstore-listing/requirements.txt"
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" --help
bash "$GK_TOOLS/playstore-listing/translate-listing.sh"
python3 "$GK_TOOLS/playstore-listing/validate_screenshots.py"

# Play Console first-publish snapshot (playConsole in project.manifest.json)
./scripts/play-console.sh validate
./scripts/play-console.sh checklist
# or:
python3 "$GK_TOOLS/playstore-listing/play_console.py" validate
python3 "$GK_TOOLS/playstore-listing/play_console.py" checklist
```

Arthur and new GeoKing apps should wrap these under `scripts/` rather than vendoring a second copy.

---

## 9. Website in the monorepo (Scora pattern)

Landing lives in **`website/`** inside the Android repo. Roborazzi outputs under `screenshots/` are copied into `website/assets/` by shared tooling.

| Piece | Location |
|---|---|
| Skill | `skills/gk-website-sync/` |
| Fill script | `bin/fill_website_screenshots.py` |
| Mapping | app `website/screenshot-sources.json` |
| Screenshots CI | `templates/website-screenshots.yml` |
| Deploy Pages | `templates/cloudflare-pages.yml` |
| Deploy Workers | `templates/website-deploy-workers.yml` |

```bash
# App root — thin wrapper recommended:
#   scripts/fill_website_screenshots.py → _geoking-wrapper.sh → bin/fill_website_screenshots.py
./scripts/fill_website_screenshots.py
./gradlew generateWebsiteScreenshots -PscreenshotLocales=en,fr
```

Reference: **Arthur** (static Workers + fill map). **Scora** keeps a richer npm mockup/GIF pipeline app-local; only the copy step is shared here.
