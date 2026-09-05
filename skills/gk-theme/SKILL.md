---
name: gk-theme
description: >-
  Add System / Light / Dark UI theme preference for a GeoKing Android phone app
  (Gaston pattern: ThemeMode, Settings chips, MaterialTheme wrapper, prefs).
  Use when adding dark mode, light theme, theme setting, ThemeMode, uiThemeMode,
  ui_theme_mode, gk-theme, or wiring App theme into Settings / MainActivity.
---

# UI theme (System / Light / Dark)

Success = user can pick **System / Light / Dark** in Settings; preference
persists; phone Compose UI applies the matching Material 3 color scheme
immediately (System follows `isSystemInDarkTheme()`).

| Reference | Role |
|---|---|
| **Gaston** (`~/dev/android/_auto/gaston`) | Canonical — use this |
| **Arthur** (`~/dev/android/arthur`) | Has light+dark schemes but **no** user preference yet |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-theme/`. Pair with **`gk-settings`** for the Settings hub.

```
~/dev/android/
├── geoking-tools/
├── _auto/gaston/          # reference
└── <app>/
    └── androidApp/…/
        ├── ThemeMode + prefs (or SettingsManager)
        ├── ui/theme/*Theme.kt
        └── ui/…/SettingsScreen.kt   # Theme page + FilterChips
```

## Progress checklist

```
- [ ] 1. ThemeMode enum { System, Light, Dark }
- [ ] 2. Persist ui_theme_mode (SharedPreferences / SettingsManager)
- [ ] 3. AppTheme(themeMode) → MaterialTheme + light/dark ColorScheme
- [ ] 4. MainActivity: collect preference → AppTheme(themeMode = …)
- [ ] 5. Settings: Theme page + FilterChips; Main row shows current label
- [ ] 6. EN (+ FR) strings
- [ ] 7. Optional: Android Auto theme list (Gaston AutoThemeSelectionScreen)
```

## Default decisions

| Choice | Default | Notes |
|---|---|---|
| Modes | **System, Light, Dark** | Not a boolean dark-only toggle |
| Storage key | `ui_theme_mode` | Enum `.name` string |
| Default | `ThemeMode.System` | |
| Settings UI | `FilterChip` row | Gaston `ThemeConfig` |
| Navigation | `SettingsScreenPage.Theme` stack page | Via `gk-settings` hub |
| Map / basemap themes | **Out of scope** | Gaston `MapTheme` / `mapThemeMode` are product-specific |
| Surfaces | Phone Activity | Auto optional |

Do **not** ship map style pickers or night-driving map copy unless the product has maps.

---

## 1. ThemeMode + persistence

```kotlin
enum class ThemeMode { System, Light, Dark }
```

In settings data class:

```kotlin
val uiThemeMode: ThemeMode = ThemeMode.System,
```

Load / save:

```kotlin
val uiThemeMode = try {
    ThemeMode.valueOf(prefs.getString("ui_theme_mode", ThemeMode.System.name)!!)
} catch (_: Exception) { ThemeMode.System }

prefs.edit().putString("ui_theme_mode", sanitized.uiThemeMode.name).apply()
```

Gaston: `SettingsManager.kt` + `AppSettings.uiThemeMode`. Minimal apps can keep a tiny prefs helper instead of a full `AppSettings`.

---

## 2. Compose theme wrapper

```kotlin
@Composable
fun AppTheme(
    themeMode: ThemeMode = ThemeMode.System,
    content: @Composable () -> Unit,
) {
    val dark = when (themeMode) {
        ThemeMode.Dark -> true
        ThemeMode.Light -> false
        ThemeMode.System -> isSystemInDarkTheme()
    }
    MaterialTheme(
        colorScheme = if (dark) AppDarkScheme else AppLightScheme,
        content = content,
    )
}
```

Define both `lightColorScheme` and `darkColorScheme` (reuse the app’s existing brand colors). Arthur already has both schemes — pass `themeMode` instead of hardcoding `darkTheme = true`.

Canonical Gaston: `ui/dashboard/PlaystoreDashboardTheme.kt` → `GastonTheme(themeMode)`.

---

## 3. MainActivity wiring

```kotlin
val settings by settingsManager.settings.collectAsState()
AppTheme(themeMode = settings.uiThemeMode) {
    // … screens …
}
```

Every phone surface that builds its own root should use the same preference (or inherit under one `AppTheme`).

---

## 4. Settings UI (requires gk-settings)

1. Add `SettingsScreenPage.Theme`.
2. Main menu row:

```kotlin
SettingsItem(
    label = stringResource(R.string.screen_theme),
    value = settings.uiThemeMode.displayLabel(),
    onClick = { onNavigate(SettingsScreenPage.Theme) },
)
```

3. Theme page — Gaston `ThemeConfig`:

```kotlin
@Composable
fun ThemeConfig(settings: AppSettings, onUpdate: (AppSettings) -> Unit) {
    Column(Modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Text(stringResource(R.string.screen_app_theme), style = MaterialTheme.typography.titleMedium)
        Row(Modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            ThemeMode.entries.forEach { mode ->
                FilterChip(
                    selected = settings.uiThemeMode == mode,
                    onClick = { onUpdate(settings.copy(uiThemeMode = mode)) },
                    label = { Text(mode.displayLabel()) },
                )
            }
        }
    }
}

@Composable
fun ThemeMode.displayLabel(): String = when (this) {
    ThemeMode.System -> stringResource(R.string.theme_mode_system)
    ThemeMode.Light -> stringResource(R.string.theme_mode_light)
    ThemeMode.Dark -> stringResource(R.string.theme_mode_dark)
}
```

Save on chip click (Gaston: `settingsManager.saveSettings(…)` / `saveSettingsWithThemeCheck`).

---

## 5. Strings (minimum)

| Key | EN | FR |
|---|---|---|
| `screen_theme` | Theme | Thème |
| `screen_app_theme` | App theme | Thème de l'application |
| `theme_mode_system` | System | Système |
| `theme_mode_light` | Light | Clair |
| `theme_mode_dark` | Dark | Sombre |

Optional map-night footnote (`settings_theme_night_maps`) — Gaston only.

---

## 6. Optional Android Auto

Gaston `auto/AutoThemeSelectionScreen.kt`: `ListTemplate` of `ThemeMode.entries`, save + `invalidate()`. Only add if the car app already has settings templates.

---

## Verify

- Settings → Theme → Light / Dark / System; UI colors flip without restart
- Kill process; preference still applied
- System mode follows device dark/light
- Main Settings row shows the current mode label

## Agent rules

- Prefer **Gaston** phone pattern; do not copy map basemap themes.
- If Settings hub is missing, run **`gk-settings`** first, then add the Theme page.
- Keep `ThemeMode` as a three-value enum — do not invent “auto / battery / schedule” modes unless asked.
