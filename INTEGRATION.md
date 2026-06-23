# Intégrer geoking-tools + geoking-ci dans une nouvelle app

Guide pas-à-pas pour brancher release Play, OAuth/Firebase, scripts locaux et CI GitHub Actions sur un projet Android KMP (Compose).

**Référence :** [vincent](https://github.com/ludoo0d0a/vincent) est l'app modèle.

### Bootstrap en une commande

Depuis la racine de la nouvelle app :

```bash
../geoking-tools/templates/bootstrap-new-app.sh --package fr.geoking.myapp --name MyApp
```

Puis complète `scripts/project.manifest.json` et lance `./scripts/setup-release.sh`. Le reste de ce guide détaille chaque étape manuellement.

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

Alternative : `export GEOKING_TOOLS=~/chemin/vers/geoking-tools` si le clone n'est pas sibling.

---

## Checklist rapide

- [ ] 1. Créer `scripts/` + `project.manifest.json`
- [ ] 2. Copier les wrappers shell + `whatsnew.py`
- [ ] 3. Mettre à jour `.gitignore`
- [ ] 4. Adapter `composeApp/build.gradle.kts` (secrets, signing, version)
- [ ] 5. Ajouter `playstore/version.properties` + `playstore/whatsnew.xml`
- [ ] 6. Ajouter les workflows CI dans `.github/workflows/`
- [ ] 7. Lancer `./scripts/setup-release.sh` (wizard secrets + keystore)
- [ ] 8. Pousser `geoking-ci` sur GitHub avant le premier run CI

---

## 1. Manifest projet

Crée `scripts/project.manifest.json` — source de vérité pour package, consoles et build.

Copie le template :

```bash
cp ../geoking-tools/templates/project.manifest.json scripts/project.manifest.json
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

Les URLs Play suivent le motif :
`https://play.google.com/console/u/0/developers/{developerId}/app/{appId}/app-dashboard`

---

## 2. Wrappers scripts

Les scripts vivent dans **geoking-tools** ; chaque app garde des wrappers minces dans `scripts/`.

### Copie automatique

Depuis la racine de ton app :

```bash
mkdir -p scripts
cp ../geoking-tools/templates/project.manifest.json scripts/
cp ../geoking-tools/templates/_geoking-wrapper.sh scripts/
cp ../geoking-tools/templates/whatsnew.py scripts/

for s in setup-release show-secrets verify-oauth gen-keystore build-aab deploy-device adb-reconnect; do
  cp "../geoking-tools/templates/script-stub.sh" "scripts/$s.sh"
done

chmod +x scripts/*.sh scripts/whatsnew.py
```

### Structure résultante

```
my-new-app/scripts/
├── _geoking-wrapper.sh      # résout geoking-tools, délègue
├── project.manifest.json    # config spécifique à l'app
├── setup-release.sh         # stub → geoking-tools/bin/setup-release.sh
├── show-secrets.sh
├── verify-oauth.sh
├── gen-keystore.sh
├── build-aab.sh
├── deploy-device.sh
├── adb-reconnect.sh
└── whatsnew.py              # stub Python
```

### Test

```bash
./scripts/verify-oauth.sh    # après avoir placé google-services.json
./scripts/setup-release.sh   # wizard complet (keystore, Play, Firebase…)
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

CI injecte `VERSION_CODE=${{ github.run_number }}` automatiquement via geoking-ci.

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

## 6. GitHub Actions

Les workflows tournent **dans le dépôt de l'app** (inline). GitHub Free ne permet pas
`workflow_call` depuis un dépôt `geoking-ci` privé — on copie les YAML depuis les
templates ; **[geoking-ci](https://github.com/ludoo0d0a/geoking-ci)** reste la référence
canonique à synchroniser.

### Bootstrap ou copie manuelle

```bash
mkdir -p .github/actions/setup-gradle .github/workflows
cp ../geoking-tools/templates/setup-gradle/action.yml .github/actions/setup-gradle/
cp ../geoking-tools/templates/android-ci.yml .github/workflows/
cp ../geoking-tools/templates/release-play.yml .github/workflows/
```

Édite `artifact_name` et `package_name` dans les workflows.

> **GitHub Team+** avec `geoking-ci` public ou partagé : tu peux utiliser
> `uses: OWNER/geoking-ci/.github/workflows/android-ci.yml@main` à la place.
> Voir [geoking-ci/README.md](https://github.com/ludoo0d0a/geoking-ci).

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

---

## 7. Première release — ordre recommandé

1. **Firebase** — créer le projet, ajouter l'app Android (`package`), télécharger `google-services.json` → `composeApp/`
2. **Keystore** — `./scripts/setup-release.sh keystore` (ou `gen-keystore.sh --gh`)
3. **Play Console** — créer l'app, noter `developerId` + `appId` dans le manifest
4. **Compte de service** — `./scripts/setup-release.sh play`
5. **OAuth** — `./scripts/setup-release.sh firebase` puis `oauth` ; enregistrer SHA-1 debug + Play App Signing
6. **Vérifier** — `./scripts/setup-release.sh verify`
7. **CI** — push sur `main`, vérifier Actions
8. **Play** — première upload internal via CI ou `./scripts/build-aab.sh` en local

---

## 8. Scripts locaux utiles

| Commande | Quand l'utiliser |
|---|---|
| `./scripts/deploy-device.sh` | Build + install sur téléphone (USB ou Wi-Fi adb) |
| `./scripts/adb-reconnect.sh -s IP:5555` | Garder adb sans fil actif pendant le dev |
| `./scripts/build-aab.sh` | AAB signé local + vérif empreinte avant upload manuel |
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
| `geoking-tools introuvable` | Clone sibling ou `export GEOKING_TOOLS=…` |
| CI : `workflow not found` | GitHub Free + `geoking-ci` privé : utilise les workflows inline (`templates/`), pas `workflow_call` |
| CI : `gradle: command not found` | Normal si pas de wrapper — geoking-ci provisionne Gradle 8.13 |
| Google Sign-In échoue en local | SHA-1 debug manquant dans Firebase/GCP → `./scripts/verify-oauth.sh` |
| Google Sign-In échoue sur Play | SHA-1 **App signing** (pas upload) dans Firebase → Play Console → Intégrité |
| `release-play.yml n'injecte PAS WEB_CLIENT_ID` | Le workflow doit utiliser `geoking-ci` avec `secrets: inherit` |
| AAB rejeté (signature) | `./scripts/build-aab.sh` compare l'empreinte avant upload |

---

## Fichiers template

Tous dans `geoking-tools/templates/` :

| Fichier | Destination dans l'app |
|---|---|
| `project.manifest.json` | `scripts/project.manifest.json` |
| `_geoking-wrapper.sh` | `scripts/_geoking-wrapper.sh` |
| `script-stub.sh` | `scripts/<nom>.sh` (un par script) |
| `whatsnew.py` | `scripts/whatsnew.py` |
| `setup-gradle/action.yml` | `.github/actions/setup-gradle/action.yml` |
| `android-ci.yml` | `.github/workflows/android-ci.yml` |
| `release-play.yml` | `.github/workflows/release-play.yml` |
