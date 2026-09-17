---
name: gk-debug-bar
description: >-
  Add a floating "bug" debug button that opens a full HTTP / provider traffic
  inspector overlay for a GeoKing Android phone app. Uses the shared Compose
  library fr.geoking.tools:debug-bar from geoking-tools (includeBuild). Use when
  adding a debug bar, network inspector, HTTP logger, floating bug button,
  gk-debug-bar, DebugLogOverlay, or FloatingDebugBar.
---

# HTTP debug bar (floating bug button)

Success = a debug-only floating bug FAB opens a big overlay (Network + Providers
+ Data Usage tabs) via **`fr.geoking.tools:debug-bar`**. Capture (Ktor/OkHttp →
store) stays in the app; the library is UI-only. Gate behind a developer /
verbose flag.

| Piece | Location |
|---|---|
| **UI library** | `geoking-tools/android/debug-bar` → `fr.geoking.tools:debug-bar` |
| **Reference consumer** | Gaston (`GastonDebugLogOverlay` adapter) |
| **Capture (OkHttp)** | Arthur-style `DebugInterceptor` + `DebugLogger` (see below) |
| **Capture (Ktor)** | Gaston `AppModule` `ResponseObserver` → `DebugLogStore` |

Resolve tools: `$GK_TOOLS` → `../geoking-tools` → `../../geoking-tools` (Gaston is under `_auto/`).

```
~/dev/android/
├── geoking-tools/
│   └── android/
│       └── debug-bar/          # Compose library (FAB + overlay)
├── _auto/gaston/               # includeBuild consumer
└── <app>/
```

## Progress checklist

```
- [ ] 1. includeBuild geoking-tools/android + implementation("fr.geoking.tools:debug-bar")
- [ ] 2. App-side store / interceptor captures network (and optional provider) logs
- [ ] 3. Thin adapter: map store → library models + wire cache/clear callbacks
- [ ] 4. Gate behind verbose/developer flag in MainActivity
- [ ] 5. Do not copy DebugLogOverlay.kt — edit the library in geoking-tools
```

## 1. Import the library (includeBuild)

In the app’s `settings.gradle.kts`:

```kotlin
val gkToolsRoot = System.getenv("GK_TOOLS")
    ?: listOf("../geoking-tools", "../../geoking-tools")
        .map { rootDir.resolve(it) }
        .firstOrNull { it.resolve("android").isDirectory }
        ?.absolutePath
    ?: error("geoking-tools not found; clone sibling or set GK_TOOLS")

includeBuild("$gkToolsRoot/android") {
    dependencySubstitution {
        substitute(module("fr.geoking.tools:debug-bar"))
            .using(project(":debug-bar"))
    }
}
```

In the phone module `build.gradle.kts`:

```kotlin
implementation("fr.geoking.tools:debug-bar")
```

**Updates:** edit sources under `geoking-tools/android/debug-bar`, then rebuild the app.
No version bump — composite build compiles from source. Share changes by
committing/pushing **geoking-tools**; apps only keep the includeBuild lines.
CI: checkout `geoking-tools` next to the app (or set `GK_TOOLS`) before Gradle.

## 2. Public UI API

```kotlin
@Composable
fun DebugLogOverlay(
    logs: List<NetworkLog>,
    providerTraces: List<ProviderTraceEntry>,
    hostConsumption: Map<String, HostDataConsumption>,
    totalBytesSent: Long,
    totalBytesReceived: Long,
    disableCache: Boolean,
    onDisableCacheChange: (Boolean) -> Unit,
    onClearCaches: () -> Unit,
    onClearLogs: () -> Unit,
    onResetDataConsumption: () -> Unit,
    modifier: Modifier = Modifier,
    detectedCountries: String? = null,
)
```

Models live in `fr.geoking.tools.debugbar.model`. Strings are hardcoded English
(debug-only). Also exports `JsonTree` for reusable JSON rendering.

## 3. Adapter pattern (Gaston)

Keep capture in the app (`DebugLogStore` / `ProviderTraceStore` in `:shared`).
Map into library models and wire Settings / CacheManager:

```kotlin
@Composable
fun AppDebugLogOverlay(...) {
    val logs by DebugLogStore.logs.collectAsState()
    // … map to fr.geoking.tools.debugbar.model.* …
    DebugLogOverlay(
        logs = mappedLogs,
        providerTraces = mappedTraces,
        hostConsumption = mappedConsumption,
        totalBytesSent = totalBytesSent,
        totalBytesReceived = totalBytesReceived,
        disableCache = settings.disableCache,
        onDisableCacheChange = { … },
        onClearCaches = { … },
        onClearLogs = { DebugLogStore.clearAll() },
        onResetDataConsumption = { DebugLogStore.resetDataConsumption() },
    )
}
```

Resolve large request/response bodies in the adapter (Gaston:
`DebugLogPayloadCache.get` → fill `NetworkLog.requestBody` /
`responseBody` before passing to the overlay).

## 4. Capture (app-side)

### OkHttp (Arthur pattern)

Extend `DebugQueryItem` / `DebugLogger` with host/headers/body fields. Wire
`DebugInterceptor` (`peekBody`, textual Content-Types only, truncate) +
`HttpCacheController` / `CacheBypassInterceptor`. Prefer this when the engine
is `HttpClient(OkHttp)`.

### Ktor (Gaston pattern)

`ResponseObserver` + request body capture → `DebugLogStore.addLog(NetworkLog(…))`.
Provider pipeline → `ProviderTraceStore.add(…)`.

## 5. Gate in MainActivity

```kotlin
if (settings.debugBarEnabled || settings.verbose) {
    AppDebugLogOverlay(modifier = Modifier.align(Alignment.TopEnd))
}
```

Pair with **`gk-settings`** Developer page for the toggle. Do not ship enabled
in release for end users.

## Verify

- Developer flag on → bug FAB appears.
- Tap → Network / Providers / Data Usage tabs work.
- Disable cache / clear cache / clear logs / reset consumption hit app callbacks.
- Edit `geoking-tools/android/debug-bar` → app rebuild picks up UI changes.

## Agent rules

- **Never copy** the overlay into the app — always depend on `fr.geoking.tools:debug-bar`.
- UI changes go in **geoking-tools**; app changes are adapter + capture only.
- Don’t gate behind a flag that is on by default in release builds.
- Don’t add `material-icons-extended` solely for this in the app — the library already depends on it.
