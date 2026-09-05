---
name: gk-about-page
description: >-
  Add a GeoKing phone About page (Gaston/Arthur Settings stack pattern): version
  name/code, build date, privacy, terms, OSS licenses (AboutLibraries), optional
  Used APIs. Use when adding About, open-source licenses, LibrariesContainer,
  about_terms, about_privacy, BUILD_DATE, gk-about-page, or Settings → About.
---

# About page (phone)

Success = Settings stack can open **About** with version + build info, privacy /
terms links (`ACTION_VIEW`), an **OSS licenses** subpage (AboutLibraries
Compose M3), and optional **Used APIs** attributions.

| Reference | Role |
|---|---|
| **Arthur** (`~/dev/android/arthur`) | Canonical minimal About + licenses + legal links |
| **Gaston** (`~/dev/android/_auto/gaston`) | Settings stack / About rows / UsedApis / `BUILD_DATE` (no OSS lib yet) |
| **gk-settings** | Host Settings hub (gear, stack, Main menu) — wire About into it |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-about-page/`.

```
~/dev/android/
├── geoking-tools/
├── _auto/gaston/          # Settings / About row pattern
└── <app>/
    ├── androidApp/…/ui/screens/SettingsScreen.kt
    ├── website/privacy.html + terms.html
    └── scripts/project.manifest.json  # urls.website.policy / terms
```

## Progress checklist

```
- [ ] 1. Settings hub exists (or run gk-settings first)
- [ ] 2. BuildConfig BUILD_DATE (+ VERSION_NAME / VERSION_CODE already from AGP)
- [ ] 3. AboutLibraries plugin.android + compose-m3 (match Compose BOM line)
- [ ] 4. SettingsScreenPage.About (+ Licenses) + AboutContent / LicensesContent
- [ ] 5. Website privacy.html + terms.html; footer + manifest URLs
- [ ] 6. EN (+ FR) strings
- [ ] 7. Optional: UsedApisList for product sources
```

## Default decisions

| Choice | Default | Notes |
|---|---|---|
| Host | Settings stack page | Not a NavHost destination unless app already uses one |
| Version | `BuildConfig.VERSION_NAME` + `VERSION_CODE` | Separate rows (Gaston/Arthur) |
| Build | `BuildConfig.BUILD_DATE` (`yyyy-MM-dd`) | Set in module `defaultConfig` |
| Privacy / terms | `Intent.ACTION_VIEW` to site | `https://<slug>.geoking.fr/privacy.html` + `terms.html` |
| OSS licenses | **AboutLibraries** Compose M3 | Subpage `Licenses` with `LibrariesContainer` |
| Attributions | Optional `UsedApisList` | Product APIs only — not a substitute for OSS licenses |
| Surfaces | Phone Settings UI | Skip Auto unless product asks |

Do **not** use Play `OssLicensesMenuActivity` for new GeoKing apps unless an
existing codebase already depends on it.

---

## 1. BuildConfig build date

Phone module `defaultConfig`:

```kotlin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

val buildDate = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
buildConfigField("String", "BUILD_DATE", "\"$buildDate\"")
```

Requires `buildFeatures { buildConfig = true }` (AGP also exposes `VERSION_*`).

---

## 2. AboutLibraries (OSS licenses)

Pick the line that matches the app’s Compose major (see AboutLibraries README):

| Compose | aboutlibraries |
|---|---|
| 1.10.x + AGP 9 | **14.1.0** (Arthur) |
| 1.11.x | 15.x |

`gradle/libs.versions.toml`:

```toml
aboutlibraries = "14.1.0"
# …
aboutlibraries-compose-m3 = { module = "com.mikepenz:aboutlibraries-compose-m3", version.ref = "aboutlibraries" }
# …
aboutlibraries-android = { id = "com.mikepenz.aboutlibraries.plugin.android", version.ref = "aboutlibraries" }
```

Root `build.gradle.kts`: `alias(libs.plugins.aboutlibraries.android) apply false`  
Phone module: apply the same plugin + `implementation(libs.aboutlibraries.compose.m3)`.

The `.android` plugin generates `R.raw.aboutlibraries` during the Android build.

UI (Android auto-load from `R.raw.aboutlibraries`):

```kotlin
LibrariesContainer(
    modifier = Modifier.fillMaxSize(),
)
```

Or explicit:

```kotlin
import com.mikepenz.aboutlibraries.ui.compose.android.produceLibraries

val libraries by produceLibraries(R.raw.aboutlibraries)
LibrariesContainer(libraries = libraries, modifier = Modifier.fillMaxSize())
```

Import `LibrariesContainer` from `com.mikepenz.aboutlibraries.ui.compose.m3`.

---

## 3. About + Licenses in Settings stack

```kotlin
enum class SettingsScreenPage { Main, About, Licenses /* … */ }

// when (current) {
//   About -> AboutContent(onOpenLicenses = { stack += Licenses })
//   Licenses -> LicensesContent()
// }
```

**AboutContent** (order):

1. App name headline  
2. Rows: version name, version code, build date  
3. Clickable: privacy, terms, open-source licenses (push Licenses), website  
4. Optional section: Used APIs (`ACTION_VIEW` per URL)

Keep helpers private next to Settings (Arthur/Gaston): `AboutRow`,
`AboutRowClickable`, `AboutApiRow`.

Legal URLs (constants or manifest-derived):

```kotlin
private const val PrivacyUrl = "https://<slug>.geoking.fr/privacy.html"
private const val TermsUrl = "https://<slug>.geoking.fr/terms.html"
private const val WebsiteUrl = "https://<slug>.geoking.fr"
```

---

## 4. Website + manifest

Ship static pages next to the landing:

- `website/privacy.html` (+ optional `privacy.md` source, list in `.assetsignore`)
- `website/terms.html` (+ optional `terms.md`)
- Footer links on `index.html` (EN/FR i18n keys if the landing uses them)

`scripts/project.manifest.json`:

```json
"urls": {
  "website": {
    "home": "https://<slug>.geoking.fr",
    "policy": "https://<slug>.geoking.fr/privacy.html",
    "terms": "https://<slug>.geoking.fr/terms.html"
  }
}
```

---

## 5. Strings (minimum EN / FR)

| Key | EN | FR |
|---|---|---|
| `screen_about` | About | À propos |
| `screen_licenses` | Open source licenses | Licences open source |
| `about_version_name` | Version name | Nom de version |
| `about_version_code` | Version code | Code de version |
| `about_build_date` | Build date | Date de build |
| `about_privacy` | Privacy policy | Politique de confidentialité |
| `about_terms` | Terms of service | Conditions d’utilisation |
| `about_licenses` | Open source licenses | Licences open source |
| `about_website` | Website | Site web |
| `about_used_apis` | Used APIs & services | API et services utilisés |
| `settings_about_subtitle` | Version & attributions | Version et attributions |

---

## 6. Optional Used APIs

```kotlin
data class UsedApi(val name: String, val url: String)
val UsedApisList: List<UsedApi> = listOf(/* product sources only */)
```

Gaston may add `logoUrl` + Coil; Arthur keeps name + URL. Do not list every
Maven dependency here — that is AboutLibraries’ job.

---

## Relation to gk-settings

- **gk-settings**: Settings hub chrome (gear, stack, Main menu, premium card).
- **gk-about-page**: Contents of About (+ Licenses + legal site pages).

If Settings does not exist yet, implement gk-settings first, then this skill.

---

## Verify

- Settings → About shows version name/code + build date  
- Privacy / terms open the public site pages  
- Licenses lists dependencies; back returns to About  
- Website footer links resolve after deploy  
