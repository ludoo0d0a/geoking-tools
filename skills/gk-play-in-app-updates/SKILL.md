---
name: gk-play-in-app-updates
description: >-
  Wire Play In-App Updates for a GeoKing Android phone app via shared
  fr.geoking.tools:in-app-update (flexible download, update-available
  notification tap → start update, Compose dialog, auto-complete, Settings
  manual check). Use when adding auto-update, in-app update, AppUpdateManager,
  play-app-update, gk-play-in-app-updates, Settings check for updates, or when
  Release Spine lists Play In-App Updates. Canonical consumers: Gaston + Arthur;
  Scora for multi-surface / IMMEDIATE preference.
---

# Play In-App Updates (phone)

Success = Play-installed builds check once at phone `MainActivity` startup, show
a dismissible dialog **and** an update-available notification, download
**flexibly** in the background, then **auto-`completeUpdate()`** (restart) when
downloaded. **Tapping the notification opens the app and starts the flexible
update** (no second confirm). Settings also offers **Check for updates** with
up-to-date / error feedback.

| Piece | Location |
|---|---|
| **Shared library** | `geoking-tools/android/in-app-update` → `fr.geoking.tools:in-app-update` |
| **Gaston** | Canonical consumer (phone notif + AA HUN extra + startup) |
| **Arthur** | Consumer + **Settings manual check** + feedback dialogs |
| **Scora** | Phone + Wear manager, IMMEDIATE-first (do not copy into phone-only apps) |
| Play docs | https://developer.android.com/guide/playcore/in-app-updates |

Resolve tools: `$GK_TOOLS` → `geoking-tools/` → `../geoking-tools` → `../../geoking-tools`.
This skill lives in `geoking-tools/skills/gk-play-in-app-updates/`.

```
~/dev/android/
├── geoking-tools/
│   └── android/in-app-update/   # shared helper + notification
├── _auto/gaston/                # includeBuild consumer
├── arthur/                      # includeBuild + Settings manual check
└── <app>/
```

## Progress checklist

```
- [ ] 1. includeBuild geoking-tools/android + implementation("fr.geoking.tools:in-app-update")
- [ ] 2. MainActivity: UpdateNotificationSpec, launcher, consumeLaunchIntent, check once, auto-start
- [ ] 3. Compose UpdateAvailableDialog (skip when autoStartUpdate) + in-progress indicator
- [ ] 4. Settings “Check for updates” + up-to-date / error feedback dialogs
- [ ] 5. EN (+ FR) strings + POST_NOTIFICATIONS permission
- [ ] 6. Optional: AA via CarAppExtender on the same notif (Gaston); IMMEDIATE / Wear (Scora)
```

## Default decisions (phone)

| Choice | Default | Notes |
|---|---|---|
| Implementation | **`fr.geoking.tools:in-app-update`** | Do not copy helper into the app |
| Update type | **FLEXIBLE** only | User keeps using the app |
| When to check | Once in `MainActivity.onCreate` | Not every `onResume` |
| Notification | On availability | Tap → `EXTRA_START_UPDATE` → `maybeAutoStartUpdate` |
| Manual check | Settings → `checkForUpdate(manual = true)` | Re-prompt; feedback if up to date / error |
| Gate | Play Store builds only | `BuildConfig.IS_PLAYSTORE_DISTRIBUTION` if present |
| After download | Auto `completeUpdate()` | No “Restart” snackbar |
| Dismiss | Session flag | Cancel / Update stop auto re-prompt this process |
| Activity Result | `StartIntentSenderForResult` | Required for phone apps |

Do **not** copy Scora’s Wear match-gating or IMMEDIATE preference unless the app is multi-APK / needs forced update.

---

## 1. Import the library (includeBuild)

In the app’s `settings.gradle.kts`:

```kotlin
val gkToolsRoot = System.getenv("GK_TOOLS")
    ?: listOf("geoking-tools", "../geoking-tools", "../../geoking-tools")
        .map { rootDir.resolve(it) }
        .firstOrNull { it.resolve("android").isDirectory }
        ?.absolutePath
        ?: error("geoking-tools not found; clone sibling or set GK_TOOLS")

includeBuild("$gkToolsRoot/android") {
    dependencySubstitution {
        substitute(module("fr.geoking.tools:in-app-update"))
            .using(project(":in-app-update"))
    }
}
```

Phone module `build.gradle.kts`:

```kotlin
implementation("fr.geoking.tools:in-app-update")
// Play app-update deps come transitively (api); keep explicit catalog deps if preferred.
```

Optional thin aliases (Gaston/Arthur):

```kotlin
package fr.geoking.<app>.update
typealias CheckFeedback = fr.geoking.tools.inappupdate.CheckFeedback
typealias InAppUpdateHelper = fr.geoking.tools.inappupdate.InAppUpdateHelper
```

---

## 2. Shared API

Package: `fr.geoking.tools.inappupdate`.

```kotlin
class InAppUpdateHelper(
    context: Context,
    notificationSpec: UpdateNotificationSpec? = null,
    onUpdateAvailableExtra: (() -> Unit)? = null, // e.g. AA HUN
) {
    val updateAvailable: StateFlow<AppUpdateInfo?>
    val installStatus: StateFlow<Int>
    val checkFeedback: StateFlow<CheckFeedback>
    val autoStartUpdate: StateFlow<Boolean>
    fun consumeLaunchIntent(intent: Intent?)
    fun maybeAutoStartUpdate(launcher: ActivityResultLauncher<IntentSenderRequest>): Boolean
    fun checkForUpdate(manual: Boolean = false)
    fun startUpdate(info: AppUpdateInfo, launcher: ActivityResultLauncher<IntentSenderRequest>)
    fun completeUpdate()
    fun dismissUpdate()
    fun resetCheckFeedback()
    fun unregister()
}

data class UpdateNotificationSpec(
    channelId: String,
    channelName: String,
    @DrawableRes smallIcon: Int,
    title: String,
    message: String,
    launchActivityClass: Class<out Activity>,
    notificationId: Int = …,
    configureBuilder: (NotificationCompat.Builder) -> Unit = {}, // e.g. CarAppExtender
)
```

Notification content intent launches `launchActivityClass` with
`InAppUpdateIntents.EXTRA_START_UPDATE=true`. Host calls `consumeLaunchIntent` then
`maybeAutoStartUpdate` when `updateAvailable` is ready.

---

## 3. MainActivity wiring

```kotlin
private val inAppUpdateHelper by lazy {
    InAppUpdateHelper(
        context = applicationContext,
        notificationSpec = UpdateNotificationSpec(
            channelId = "<app>_updates",
            channelName = getString(R.string.update_available_title),
            smallIcon = R.drawable.…,
            title = getString(R.string.update_available_title),
            message = getString(R.string.update_available_message),
            launchActivityClass = MainActivity::class.java,
        ),
        // Gaston: add CarAppExtender via configureBuilder (one notif for phone + AA).
        // Do not also call a separate CarNotificationManager update notif.
    )
}

private val updateResultLauncher = registerForActivityResult(
    ActivityResultContracts.StartIntentSenderForResult()
) { /* cancel / failure: no-op */ }

override fun onCreate(...) {
    inAppUpdateHelper.consumeLaunchIntent(intent)
    if (BuildConfig.IS_PLAYSTORE_DISTRIBUTION) { // omit gate if flag missing
        inAppUpdateHelper.checkForUpdate()
    }
    setContent {
        val updateAvailable by inAppUpdateHelper.updateAvailable.collectAsState()
        val autoStartUpdate by inAppUpdateHelper.autoStartUpdate.collectAsState()
        LaunchedEffect(updateAvailable, autoStartUpdate) {
            if (autoStartUpdate && updateAvailable != null) {
                inAppUpdateHelper.maybeAutoStartUpdate(updateResultLauncher)
            }
        }
        // dialog only when updateAvailable != null && !autoStartUpdate
        // onUpdate → startUpdate; onCancel → dismissUpdate
        // Settings → checkForUpdate(manual = true) + checkFeedback dialogs
    }
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    inAppUpdateHelper.consumeLaunchIntent(intent)
}

override fun onDestroy() {
    inAppUpdateHelper.unregister()
    super.onDestroy()
}
```

Optional hardening: in `onResume`, if `installStatus == DOWNLOADED`, call `completeUpdate()`.

Declare `POST_NOTIFICATIONS` in the manifest. On API 33+, the notifier no-ops if
permission is denied (request at a suitable UX moment if desired).

---

## 4. UI + strings

1. **Dialog** — Material 3; Cancel + Update. Skip when `autoStartUpdate`.
2. **In progress** — full-width banner **above** current screens (`UpdateInProgressBanner`), not top-bar title text (cramped → vertical glyphs).
3. **Settings row** — `settings_check_update` → `checkForUpdate(manual = true)`.
4. **Manual feedback** — `UpToDate` / `Error` → one-button OK; `resetCheckFeedback()`.
5. **Notification** — **one** shade entry (library notifier). Apps with Android Auto add `CarAppExtender` via `UpdateNotificationSpec.configureBuilder`; do **not** post a second car-only notification.

| Key | EN | FR |
|---|---|---|
| `update_available_title` | Update available | Mise à jour disponible |
| `update_available_message` | A new version of \<App\> is available… | Une nouvelle version de \<App\> est disponible… |
| `update_in_progress` | Update in progress | Mise à jour en cours |
| `settings_check_update` | Check for updates | Vérifier les mises à jour |
| `update_check_up_to_date` | You're up to date | Vous êtes à jour |
| `update_check_error_title` | Update check | Vérification des mises à jour |
| `update_check_ok` | OK | OK |
| `action_update` | Update | Mettre à jour |
| `action_cancel` | Cancel | Annuler |

---

## 5. Optional Scora extras

| Extra | When |
|---|---|
| Prefer **IMMEDIATE**, else flexible | Forced / high-priority updates |
| Shared manager phone + Wear | Dual APK |
| `inAppUpdatePriority: 5` on Play upload | Help Play allow IMMEDIATE |

Phone-only GeoKing apps: **skip** this section.

---

## Agent rules

- Edit the library in **geoking-tools** — do not fork `InAppUpdateHelper` into apps.
- Prefer **Gaston** for startup + AA extra; **Arthur** for Settings manual check + feedback.
- Deps alone are not enough — Activity + notification tap + dialog + Settings + auto-complete required.
- Updates only work for **Play-installed** builds. Sideload / debug: fail soft.
- Never block first frame on the update Task.
- Do not commit secrets or change Play track config unless asked.

## Verify

1. Install from Play internal track (version N).
2. Upload N+1 to the same track.
3. Cold start N → dialog **and** notification.
4. Tap notification → flexible update starts (no dialog).
5. Cold start → dialog → Update → download indicator → restart on N+1.
6. Cancel once → no auto re-prompt until process death; Settings check still re-prompts.
7. Sideload debug APK → no crash.
