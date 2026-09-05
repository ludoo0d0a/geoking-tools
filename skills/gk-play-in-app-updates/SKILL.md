---
name: gk-play-in-app-updates
description: >-
  Wire Play In-App Updates for a GeoKing Android phone app (flexible download,
  Compose dialog, auto-complete). Use when adding auto-update, in-app update,
  AppUpdateManager, play-app-update, gk-play-in-app-updates, or when Release
  Spine lists Play In-App Updates. Canonical phone pattern: Gaston; Scora for
  multi-surface / Settings check / IMMEDIATE preference.
---

# Play In-App Updates (phone)

Success = Play-installed builds check once at phone `MainActivity` startup, show
a dismissible dialog, download **flexibly** in the background, then
**auto-`completeUpdate()`** (restart) when downloaded.

| Reference | Role |
|---|---|
| **Gaston** (`~/dev/android/_auto/gaston`) | Canonical **phone** pattern — use this |
| **Scora** (`~/dev/android/scora`) | Phone + Wear manager, IMMEDIATE-first, Settings manual check, upload `inAppUpdatePriority` |
| Play docs | https://developer.android.com/guide/playcore/in-app-updates |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-play-in-app-updates/`.

```
~/dev/android/
├── geoking-tools/
├── _auto/gaston/          # phone reference
├── scora/                 # multi-surface / optional extras
└── <app>/
    └── androidApp/ (or app/) …/update/InAppUpdateHelper.kt
```

## Progress checklist

```
- [ ] 1. Catalog deps play-app-update + ktx 2.1.0 on the phone module
- [ ] 2. InAppUpdateHelper (StateFlow + flexible + auto-complete)
- [ ] 3. MainActivity: launcher, check once (Play-gated), unregister onDestroy
- [ ] 4. Compose UpdateAvailableDialog + in-progress indicator
- [ ] 5. EN (+ FR) strings
- [ ] 6. Optional: Settings manual check / IMMEDIATE / inAppUpdatePriority (Scora)
```

## Default decisions (phone)

| Choice | Default | Notes |
|---|---|---|
| Update type | **FLEXIBLE** only | Gaston; user keeps using the app |
| When to check | Once in `MainActivity.onCreate` | Not every `onResume` |
| Gate | Play Store builds only | `BuildConfig.IS_PLAYSTORE_DISTRIBUTION` if the app has it; else always check (no-op off Play) |
| After download | Auto `completeUpdate()` | No “Restart” snackbar |
| Dismiss | Session flag | Cancel / Update both stop re-prompt this process |
| Activity Result | `StartIntentSenderForResult` | Do not use deprecated Activity+requestCode API for new phone apps |
| Surfaces | Phone Activity only | Skip Auto (no Activity UI) / ambient TV unless product asks |

Do **not** copy Scora’s Wear match-gating or IMMEDIATE preference unless the app is multi-APK / needs forced update.

---

## 1. Dependencies

`gradle/libs.versions.toml`:

```toml
play-app-update = "2.1.0"
# …
play-app-update = { module = "com.google.android.play:app-update", version.ref = "play-app-update" }
play-app-update-ktx = { module = "com.google.android.play:app-update-ktx", version.ref = "play-app-update" }
```

Phone module `build.gradle.kts`:

```kotlin
implementation(libs.play.app.update)
implementation(libs.play.app.update.ktx)
```

---

## 2. Helper (Gaston shape)

Package: `fr.geoking.<app>.update.InAppUpdateHelper`.

Responsibilities:

- `updateAvailable: StateFlow<AppUpdateInfo?>` — drives the dialog
- `installStatus: StateFlow<Int>` — drives in-progress UI (`PENDING` / `DOWNLOADING` / `INSTALLING`)
- Register `InstallStateUpdatedListener` in `init`; `unregister()` from `onDestroy`
- `checkForUpdate()`: skip if dismissed or dialog already showing; if `DOWNLOADED` → `completeUpdate()`; if `UPDATE_AVAILABLE` + flexible allowed → emit info
- `startUpdate(info, launcher)`: flexible `AppUpdateOptions` + `startUpdateFlowForResult`; clear dialog; set dismissed
- `dismissUpdate()`: session dismiss without starting

Core API (keep this surface; adapt logging to the app):

```kotlin
class InAppUpdateHelper(context: Context) {
    val updateAvailable: StateFlow<AppUpdateInfo?>
    val installStatus: StateFlow<Int>
    fun checkForUpdate()
    fun startUpdate(info: AppUpdateInfo, launcher: ActivityResultLauncher<IntentSenderRequest>)
    fun completeUpdate()
    fun dismissUpdate()
    fun unregister()
}
```

Copy implementation from Gaston:

`_auto/gaston/androidApp/src/main/kotlin/fr/geoking/gaston/update/InAppUpdateHelper.kt`

---

## 3. MainActivity wiring

```kotlin
private val inAppUpdateHelper by lazy { InAppUpdateHelper(applicationContext) }

private val updateResultLauncher = registerForActivityResult(
    ActivityResultContracts.StartIntentSenderForResult()
) { /* cancel / failure: no-op; user can get a later release */ }

override fun onCreate(...) {
    // …
    if (BuildConfig.IS_PLAYSTORE_DISTRIBUTION) { // omit gate if flag does not exist
        inAppUpdateHelper.checkForUpdate()
    }
    setContent {
        // collect updateAvailable → UpdateAvailableDialog
        // onUpdate → inAppUpdateHelper.startUpdate(info, updateResultLauncher)
        // onCancel → inAppUpdateHelper.dismissUpdate()
        // installStatus in progress → top bar / banner text
    }
}

override fun onDestroy() {
    inAppUpdateHelper.unregister()
    super.onDestroy()
}
```

Optional hardening (Vincent): in `onResume`, if `installStatus == DOWNLOADED`, call `completeUpdate()` so a backgrounded download still finishes.

---

## 4. UI

1. **Dialog** — Material 3; Cancel + Update. Match app chrome (Gaston uses custom `Dialog` + `Surface`; Scora uses `AlertDialog`). Title/body from strings.
2. **In progress** — non-blocking (top bar spinner + `update_in_progress`, or a slim banner). Do not block the Control Plane / main nav.
3. Wire dialog only when `updateAvailable != null`.

---

## 5. Strings (minimum)

| Key | EN | FR |
|---|---|---|
| `update_available_title` | Update available | Mise à jour disponible |
| `update_available_message` | A new version of \<App\> is available. Update now to get the latest features and improvements. | Une nouvelle version de \<App\> est disponible. Mettez à jour pour profiter des dernières fonctionnalités. |
| `update_in_progress` | Update in progress | Mise à jour en cours |
| `action_update` | Update | Mettre à jour |
| `action_cancel` | Cancel | Annuler (reuse if already present) |

Add locales the app already ships; do not invent a full i18n pass.

---

## 6. Optional Scora extras

Use only when the product needs them:

| Extra | When | Where |
|---|---|---|
| Prefer **IMMEDIATE**, else flexible, else Play Store URL | Forced / high-priority updates | Scora `InAppUpdateManager.startUpdateFlow` |
| Settings “Check for updates” + up-to-date / error feedback | Explicit manual check | `performManualCheck(showFeedback = true)` |
| Shared manager phone + Wear | Dual APK / Wear companion | Scora `shared/.../InAppUpdateManager.kt` |
| Defer check while critical UX runs | e.g. live match | `isMatchInProgress` gate |
| `inAppUpdatePriority: 5` on Play upload | Help Play allow IMMEDIATE | release workflow `upload-google-play` input |

Phone-only GeoKing apps (Arthur, Gaston, Vincent-style): **skip** this section.

---

## Agent rules

- Prefer **Gaston** for new phone wiring; do not drag Wear/match code into phone-only apps.
- Deps alone are not enough — Activity + Compose dialog + auto-complete required.
- Updates only work for **Play-installed** builds (internal/closed/production). Sideload / debug: API no-ops or errors; fail soft.
- Never block first frame on the update Task; check async after UI is up.
- Do not commit secrets or change Play track config unless asked.

## Verify

1. Install from Play internal track (version N).
2. Upload N+1 to the same track.
3. Cold start N → dialog → Update → download indicator → app restarts on N+1.
4. Cancel once → no re-prompt until process death.
5. Sideload debug APK → no crash (gate or soft failure).
