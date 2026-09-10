---
name: gk-debug-bar
description: >-
  Add a floating "bug" debug button that opens a full HTTP traffic inspector
  overlay for a GeoKing Android phone app (Arthur pattern: FAB → big floating
  window, domain filter chips, cache hit/miss, headers/payload/response,
  searchable JSON tree, full-page mode). Use when adding a debug bar, network
  inspector, HTTP logger, floating bug button, gk-debug-bar, DebugLogOverlay,
  FloatingDebugBar, or cache hit/miss visibility for OkHttp/Ktor requests.
---

# HTTP debug bar (floating bug button)

Success = a debug-only floating 🐛 button opens a big overlay window showing
every HTTP request: method/status/duration, cache **HIT/MISS**, domain filter
chips, and a details view with request/response headers + bodies rendered as
a searchable, truncation-safe JSON tree. An icon toggles the overlay between
a windowed card and true full-page. Nothing here ships to release users —
gate it behind a verbose/developer flag.

| Reference | Role |
|---|---|
| **Arthur** (`~/dev/android/arthur`) | Canonical — full inspector (headers, bodies, JSON tree+search, cache hit/miss, domain chips, full-page) |
| **Gaston** (`~/dev/android/_auto/gaston`) | Earlier, simpler overlay (`DebugLogOverlay.kt`) — floating FAB + Popup shape came from here, but no header/body capture or search |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-debug-bar/`. Pair with **`gk-settings`**'s Developer
page pattern for the verbose/developer toggle that gates the button.

```
~/dev/android/
├── geoking-tools/
├── _auto/gaston/                 # earlier, simpler reference
└── <app>/
    ├── shared/…/debug/DebugLogger.kt          # KMP-safe data model + store
    └── androidApp/…/
        ├── source/DebugInterceptor.kt         # OkHttp interceptor: capture
        ├── source/HttpCacheController.kt       # disable/clear cache control
        └── ui/components/debug/
            ├── DebugBarButton.kt              # FAB + overlay shell + full-page
            ├── NetworkLogRow.kt               # list row + domain chip
            ├── NetworkLogDetailDialog.kt       # headers/body/query-params dialog
            └── JsonTreeView.kt                # searchable JSON tree + fallback
```

## Progress checklist

```
- [ ] 1. DebugQueryItem/DebugLogger: add host/headers/body fields (shared, KMP-safe)
- [ ] 2. DebugInterceptor: capture headers + size-capped bodies + host; keep hit/miss
- [ ] 3. HttpCacheController: disable-cache toggle + evictAll(); CacheBypassInterceptor
- [ ] 4. Wire interceptors + controller into the app's single OkHttp/Ktor HttpClient
- [ ] 5. DebugBarButton: floating FAB → Popup overlay, full-page toggle
- [ ] 6. Domain filter chips + NetworkLogRow list (HIT/MISS + status + duration)
- [ ] 7. NetworkLogDetailDialog: general info, query params, headers, bodies
- [ ] 8. JsonTreeView: parse-or-fallback, truncate large containers, search+highlight
- [ ] 9. Gate behind verbose/developer flag in MainActivity; Koin/DI wiring
```

## Default decisions

| Choice | Default | Notes |
|---|---|---|
| Trigger | Floating FAB, bottom-end, `Icons.Default.BugReport` | Exported as-is from Gaston's `DebugLogOverlay.kt` (see below) — keep the icon-based FAB for now, tune later |
| Overlay | Compose `Popup(focusable = true)` + scrim | Not a `SYSTEM_ALERT_WINDOW` — stays in-process, no extra permission |
| Full-page mode | Boolean toggle swaps `Modifier.fillMaxWidth(0.95f).fillMaxHeight(0.85f)` for `Modifier.fillMaxSize()` on the same Popup content | Simplest correct implementation; no second Activity/NavHost entry |
| Data model location | `shared` KMP module (`DebugQueryItem`/`DebugLogger`) | Plain data classes only (String/Map/Boolean) — no platform API, safe even if more targets are added later |
| Body capture | OkHttp `response.peekBody(64 KiB)` for responses; buffer request body only if not one-shot | Never consumes the real stream — safe even for huge image/binary responses |
| Body truncation | 8 192 chars, `"… [truncated N chars]"` suffix | Bounds memory *and* what gets JSON-parsed; a truncated JSON body falls back to plain text, which is an accepted tradeoff |
| Binary bodies | Skipped entirely by `Content-Type` (only `text/*`, `*/json`, `*/xml`, `*/html` captured) | Images/video never get buffered into memory for logging |
| JSON tree cap | 30 children per object/array, `"… (N more truncated)"` node | Bounds render cost on huge payloads |
| Search scan cap | 5 000 nodes visited | Bounds cost of the ancestor-matching pass on pathological JSON |
| Cache HIT/MISS | `response.networkResponse == null \|\| (cacheResponse != null && networkResponse.code == 304)` | Existing OkHttp signal — only meaningful if the app actually has an `okhttp3.Cache` wired in |
| "Disable cache" | Adds `Cache-Control: no-cache` request header when toggled on | Forces revalidation every call; does not require ripping out the real cache |
| "Clear cache" | `okhttp3.Cache.evictAll()` | Only clears the HTTP disk cache — app-level caches (Room, in-memory) are a separate action if the app has them (see Gaston's `CacheManager`) |
| Icons | `material-icons-core` only (`Close`, `Refresh`, `Clear`, `Search`, `KeyboardArrowDown`, `AutoMirrored.KeyboardArrowRight`) | No new Gradle dependency; "full page" toggle and fullscreen-body link use text/emoji instead of `Fullscreen`/`BugReport` (extended-only icons) |
| Strings | Hardcoded English, no `stringResource` | Debug-only surface, never shown to end users — skip i18n unlike user-facing Settings strings |

Do **not** wire this behind a release build flag — gate it the same way the
app already gates its developer menu (Arthur: `DeveloperSettings.verbose`,
`BuildConfig.DEBUG || BuildConfig.DEBUG_DEV`).

---

## 1. Data model (shared, KMP-safe)

Extend the existing query/stats store rather than inventing a parallel one —
keep old positional/named call sites compiling by giving every new field a
default.

```kotlin
// shared/…/debug/DebugLogger.kt
data class DebugQueryItem(
    val id: Long,
    val sourceId: String,
    val url: String,
    val durationMs: Long,
    val isCached: Boolean,
    val statusCode: Int? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val host: String = "",
    val requestHeaders: Map<String, List<String>> = emptyMap(),
    val requestBody: String? = null,
    val requestBodyTruncated: Boolean = false,
    val responseHeaders: Map<String, List<String>> = emptyMap(),
    val responseBody: String? = null,
    val responseBodyTruncated: Boolean = false,
    val errorMessage: String? = null,
)
```

`DebugLogger.recordQueryEnd(...)` grows the same optional parameters and
forwards them into the item; `DebugStats` (totalQueries/cacheHits/cacheMisses/
activeQueries/recentQueries, capped via `maxRecentQueries`) is unchanged.

---

## 2. Interceptor: capture without OOM

```kotlin
// androidApp/…/source/DebugInterceptor.kt
private const val MAX_PEEK_BYTES = 64L * 1024
private const val MAX_BODY_CHARS = 8_192

class DebugInterceptor(private val debugLogger: DebugLogger) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val (requestBody, requestTruncated) = readRequestBodySnapshot(request)
        debugLogger.recordQueryStart()
        val start = System.currentTimeMillis()
        val response = try {
            chain.proceed(request)
        } catch (e: Exception) {
            debugLogger.recordQueryEnd(/* … */ errorMessage = e.message)
            throw e
        }
        val isCached = response.networkResponse == null ||
            (response.cacheResponse != null && response.networkResponse?.code == 304)
        val (responseBody, responseTruncated) = readResponseBodySnapshot(response)
        debugLogger.recordQueryEnd(/* … host, headers, bodies, isCached, statusCode … */)
        return response
    }
}
```

Key safety points (see full file for `readRequestBodySnapshot`/
`readResponseBodySnapshot`/`isTextualBody`/`truncateBody`):

- **Response body:** `response.peekBody(MAX_PEEK_BYTES).string()` — a
  snapshot read that never disturbs the real body the app is about to
  decode. Skip entirely when `Content-Type` isn't textual (images/video).
- **Request body:** only read if `!body.isOneShot()`; write to an `okio.Buffer`
  (doesn't consume the real body) and decode/truncate the same way.
- **Truncate to `MAX_BODY_CHARS`** before storing — bounds memory *and* the
  JSON parse cost downstream in the UI. A truncated JSON body may fail to
  parse; the viewer falls back to plain text in that case (see §4).

---

## 3. Cache control (disable / clear)

```kotlin
// androidApp/…/source/HttpCacheController.kt
class HttpCacheController(private val cache: okhttp3.Cache) {
    private val _disabled = MutableStateFlow(false)
    val disabled: StateFlow<Boolean> = _disabled.asStateFlow()
    fun setDisabled(value: Boolean) { _disabled.value = value }
    fun clear() { runCatching { cache.evictAll() } }
    fun stats() = HttpCacheStats(cache.size(), cache.maxSize())
}

class CacheBypassInterceptor(private val cacheController: HttpCacheController) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        return if (cacheController.disabled.value) {
            chain.proceed(request.newBuilder().header("Cache-Control", "no-cache").build())
        } else {
            chain.proceed(request)
        }
    }
}
```

Wire both into the app's single `HttpClient`/`OkHttpClient` build site, in
this order: `CacheBypassInterceptor` → `DebugInterceptor` → (existing
interceptors) → cache-forcing network interceptor, if any:

```kotlin
single { okhttp3.Cache(File(androidContext().cacheDir, "http_cache").also { it.mkdirs() }, 50 * 1024 * 1024L) }
single { HttpCacheController(get()) }
single {
    val cacheController = get<HttpCacheController>()
    val debugLogger = get<DebugLogger>()
    HttpClient(OkHttp) {
        engine { config {
            cache(get())
            addInterceptor(CacheBypassInterceptor(cacheController))
            addInterceptor(DebugInterceptor(debugLogger))
        } }
    }
}
```

If the app's networking is Ktor `HttpClient` without a direct OkHttp
interceptor chain (Gaston's shape), do the equivalent capture with Ktor's
`ResponseObserver` plugin instead — see Gaston's `AppModule.kt` for that
variant. Prefer the OkHttp-interceptor shape above when the engine is
`HttpClient(OkHttp)`, since it also gives you real `okhttp3.Cache` hit/miss
detection for free.

---

## 4. Floating button + overlay shell

**Exported as-is** from Gaston: [`DebugLogOverlay.kt`](./DebugLogOverlay.kt) —
overrides the previous illustrative emoji-FAB snippet below. This is a real,
working file (not a sketch); copy it into the target app's
`ui/components/debug/` (or equivalent) and adapt package/imports/data sources.
It keeps the `Icons.Default.BugReport` FAB rather than an emoji glyph — tune
toward the leaner Arthur pattern (headers/body capture, JSON search,
full-page mode) later.

Original illustrative shell (Arthur pattern, kept for reference only):

```kotlin
// androidApp/…/ui/components/debug/DebugBarButton.kt
@Composable
fun DebugBarButton(debugLogger: DebugLogger, cacheController: HttpCacheController, modifier: Modifier = Modifier) {
    var isExpanded by remember { mutableStateOf(false) }
    var isFullPage by remember { mutableStateOf(false) }

    if (!isExpanded) {
        FloatingActionButton(onClick = { isExpanded = true }, modifier = modifier.size(48.dp)) {
            Text("🐛", fontSize = 20.sp)
        }
    }
    if (isExpanded) {
        Popup(onDismissRequest = { isExpanded = false }, properties = PopupProperties(focusable = true)) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null,
                    onClick = { if (!isFullPage) isExpanded = false }),
                contentAlignment = Alignment.Center) {
                val cardModifier = if (isFullPage) Modifier.fillMaxSize()
                    else Modifier.fillMaxWidth(0.95f).fillMaxHeight(0.85f)
                Surface(modifier = cardModifier.clickable(/* consume, no dismiss */) { },
                    shape = if (isFullPage) RoundedCornerShape(0.dp) else RoundedCornerShape(16.dp)) {
                    DebugOverlayContent(debugLogger, cacheController, isFullPage,
                        onToggleFullPage = { isFullPage = !isFullPage }, onClose = { isExpanded = false })
                }
            }
        }
    }
}
```

`DebugOverlayContent` renders: header (counts + Cache ON/OFF chip + clear
cache + clear logs + Full page/Window chip + close), a `LazyRow` of domain
`FilterChip`s (`"All"` + `logs.map { it.host }.distinct().sorted()`), and a
`LazyColumn` of `NetworkLogRow`s that opens `NetworkLogDetailDialog` on tap.

---

## 5. Detail dialog + searchable JSON tree

`NetworkLogDetailDialog` is a standard M3 `AlertDialog` (not custom-styled
like the shell) showing: general info, query params (`HttpUrl.queryParameterNames`
+ `queryParameterValues`), request/response headers, and bodies via a shared
`JsonOrTextViewer(bodyText, showSearch = true)`:

- Tries `Json.parseToJsonElement(bodyText)`; on failure, renders plain
  monospace text (handles truncated/invalid JSON gracefully).
- Expandable tree with a 30-item-per-container cap (`"… (N more truncated)"`).
- Search box (`OutlinedTextField` + `Icons.Filled.Search`): scans the tree
  once (capped at 5 000 visited nodes) to find matching keys/values, force-
  expands only the ancestor chain of each match, and highlights the matched
  substring with `buildAnnotatedString`/`SpanStyle(background = …)`. Manual
  expand/collapse is disabled while a search is active — clear the query to
  go back to it.
- A "⤢" glyph next to each body opens the same viewer in a fullscreen
  `AlertDialog` (`DialogProperties(usePlatformDefaultWidth = false)`,
  `Modifier.fillMaxSize()`, `useLazyColumn = true`).

---

## 6. Wiring

- Koin/DI: register `HttpCacheController` next to the existing `HttpClient`
  singleton (§3).
- MainActivity: inject `DebugLogger` + `HttpCacheController`, render
  `DebugBarButton` only `if (verbose)` (or your app's developer flag),
  aligned `Alignment.BottomEnd`.
- Delete any older inline debug bar this replaces — don't keep two
  competing debug UIs (Arthur removed its old bottom-bar `FloatingDebugBar`
  entirely rather than leaving it dead alongside the new overlay).

---

## Verify

- Toggle the developer/verbose flag on → 🐛 button appears bottom-end.
- Tap it → overlay opens with request list, counts, domain chips.
- Tap "Full page" → overlay takes over the whole screen; toggle back → windowed card returns.
- Filter by a domain chip → list narrows to that host only.
- Tap a request with a JSON body → headers + body render; type in the JSON
  search box → only the matching branch auto-expands and the hit is highlighted.
- Toggle "Cache: ON/OFF" → repeat a request → previously-cached request now
  shows `MISS` every time; toggle back → `HIT` reappears on repeat calls.
- Tap "Clear HTTP cache" → next identical request is a `MISS`.
- Request a large/binary (image) URL → no OOM, body column shows nothing
  (by design — binary bodies are never buffered for logging).

## Agent rules

- Extend the existing `DebugQueryItem`/`DebugLogger` in `shared` rather than
  building a parallel network-log store — keep old call sites compiling via
  defaults.
- Never read the *real* response/request stream for logging — always use
  `peekBody`/an `okio.Buffer` snapshot so the actual app logic still gets an
  untouched body.
- Don't add `material-icons-extended` for this feature; core icons + a couple
  of emoji/text glyphs cover everything needed.
- Don't gate this behind anything that ships enabled in release builds.
