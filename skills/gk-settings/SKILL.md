---
name: gk-settings
description: >-
  Add a GeoKing phone Settings hub (Gaston pattern: stack pages, TopAppBar,
  SettingsItem menu, About). Use when adding settings, SettingsScreen, About
  page, settings gear, cd_settings, gk-settings, or wiring Paramètres /
  screen_settings into a Control Plane / MainActivity.
---

# Settings hub (phone)

Success = phone Activity can open a **Settings** overlay with stack navigation
(Main → subpages), system/back pops the stack, and **About** shows version +
privacy/website (+ optional Used APIs).

| Reference | Role |
|---|---|
| **Gaston** (`~/dev/android/_auto/gaston`) | Canonical full hub (many subpages, auth, premium, theme) |
| **Arthur** (`~/dev/android/arthur`) | Minimal GeoKing phone hub (Main + About + premium card) |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-settings/`.

```
~/dev/android/
├── geoking-tools/
├── _auto/gaston/     # full reference
└── <app>/
    └── androidApp/…/ui/screens/SettingsScreen.kt
```

## Progress checklist

```
- [ ] 1. material-icons-core (+ optional extended) on phone module
- [ ] 2. drawable ic_settings + SettingsButton
- [ ] 3. SettingsScreenPage enum + SettingsScreen (stack + BackHandler + Scaffold)
- [ ] 4. Main menu SettingsItem(s) + About (version, links, UsedApis)
- [ ] 5. Entry: gear on header / toolbar → showSettings overlay in MainActivity
- [ ] 6. EN (+ FR) strings
- [ ] 7. Optional: SettingsManager, premium card, Developer (DEBUG), deep-link stack
```

## Default decisions

| Choice | Default | Notes |
|---|---|---|
| Navigation | In-screen **stack** (`List<SettingsScreenPage>`) | Not NavHost unless app already uses it |
| Hosting | Boolean overlay in phone `MainActivity` | Gaston `showSettings`; Arthur same |
| Back | `BackHandler`: pop stack else `onDismiss` | Match TopAppBar back |
| Chrome | M3 `Scaffold` + `TopAppBar` | Title per page |
| Menu rows | `SettingsItem` = `ListItem` + chevron | Card-wrapped group on Main |
| About | Version + legal + licenses | See **gk-about-page** (BUILD_DATE, terms, AboutLibraries) |
| Persistence | Add `SettingsManager` only when prefs exist | Do not invent a mega AppSettings |
| Surfaces | Phone Activity UI | Skip Auto templates unless product asks |

Do **not** copy Gaston’s vehicle/map/toll/auth blocks into a new app unless that product needs them.

---

## 1. Dependencies

`gradle/libs.versions.toml`:

```toml
compose-material-icons = "1.7.8"
# …
compose-material-icons-core = { module = "androidx.compose.material:material-icons-core", version.ref = "compose-material-icons" }
```

Phone module:

```kotlin
implementation(libs.compose.material.icons.core)
```

Use **extended** only if you need icons outside core (Gaston uses `ChevronRight`;
Arthur stays on core with `KeyboardArrowRight`).

---

## 2. Entry affordance

Copy gear vector from Gaston:

`_auto/gaston/androidApp/src/main/res/drawable/ic_settings.xml`

```kotlin
@Composable
fun SettingsButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(onClick = onClick, modifier = modifier) {
        Icon(
            painter = painterResource(R.drawable.ic_settings),
            contentDescription = stringResource(R.string.cd_settings),
            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}
```

Place on the main screen header (Arthur: `ControlPlaneHeader(onOpenSettings = …)`).

---

## 3. SettingsScreen shape

```kotlin
enum class SettingsScreenPage { Main, About /* + product pages */ }

@Composable
fun SettingsScreen(
    onDismiss: () -> Unit,
    isPremium: Boolean = false,
    initialScreenStack: List<SettingsScreenPage>? = null,
    onInitialRouteConsumed: () -> Unit = {},
) {
    var screenStack by remember { mutableStateOf(listOf(SettingsScreenPage.Main)) }
    // LaunchedEffect(initialScreenStack) → replace stack + consume
    // BackHandler → pop or onDismiss
    // Scaffold(topBar = TopAppBar(title by page, navIcon = back))
    // when (screenStack.last()) { Main → …; About → … }
}
```

Canonical implementations:

- Full: `_auto/gaston/.../ui/SettingsScreen.kt`
- Minimal: `arthur/.../ui/screens/SettingsScreen.kt`

Shared UI primitives (keep private or extract later):

- `SettingsItem(label, value?, onClick)` — ListItem + ChevronRight
- `AboutRow` / `AboutRowClickable` — version lines + link rows
- Optional premium banner Card when `isPremium` (Gaston blue/gold)

---

## 4. MainActivity wiring

```kotlin
var showSettings by remember { mutableStateOf(false) }
when {
    showSettings -> SettingsScreen(
        onDismiss = { showSettings = false },
        isPremium = /* entitlement */,
    )
    else -> MainScreen(onOpenSettings = { showSettings = true })
}
```

Optional deep link (Gaston): keep `settingsInitialStack: List<SettingsScreenPage>?` and pass `initialScreenStack` / `onInitialRouteConsumed`.

---

## 5. About + Used APIs

Implement About contents with **gk-about-page** (version / build date, privacy,
terms, AboutLibraries licenses page, optional `UsedApisList`).

Minimum Settings strings for the hub itself:

| Key | EN | FR |
|---|---|---|
| `screen_settings` | Settings | Paramètres |
| `screen_about` | About | À propos |
| `cd_settings` | Settings | Paramètres |
| `action_back` | Back | Retour |
| `settings_about_subtitle` | Version & attributions | Version et attributions |

About/license string keys live in gk-about-page. Add premium / developer labels
only when those rows exist.

---

## 6. Strings (hub)

See table above; full About strings → gk-about-page.

---

## 7. Optional Gaston extras

| Extra | When |
|---|---|
| `SettingsManager` + `AppSettings` StateFlow | Persisted prefs beyond a few SharedPreferences keys |
| Theme System/Light/Dark | Product wants appearance toggle — skill **`gk-theme`** |
| Sources / Map / Vehicle subpages | Product has those domains |
| Google auth card on Main | Cloud sync / signed-in profile |
| `Developer` page behind `BuildConfig.DEBUG_DEV` | Debug toggles / error log |
| Auto `AutoSettingsScreen` | Car App Library settings templates |

---

## Verify

- Open gear → Settings Main → About → back → dismiss to main UI
- System back mirrors TopAppBar
- About checklist: see **gk-about-page** (version, legal links, licenses)
