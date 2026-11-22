---
name: gk-tv-remote-navigation
description: >-
  Android TV / Leanback Compose UI for GeoKing apps (Arthur, Gaston, Vincent):
  D-pad and remote-control focus, Marketplace/paywall/account screens, PackGrid
  selectOnFocus, no sliders. Use when building or reviewing TV surfaces that must
  work with a télécommande / remote.
---

# GeoKing TV remote navigation (télécommande)

## Hard rules

1. **No sliders** on TV — use chips, +/- steppers, list rows, or system controls (see workspace rule `tv-no-sliders`).
2. **Prefer full-screen routes** over Material dialogs for purchase / account / paywall — dialogs trap focus poorly with D-pad.
3. **Focus is the selection** on TV: use `selectOnFocus = true` on grids; do not require a separate click just to highlight.
4. **Request focus after composition** via `LaunchedEffect`, never in the composable body.
5. **Commerce on phone + TV** for Arthur Marketplace (ADR 0009); never on Android Auto.

## Arthur patterns to reuse

| Surface | Pattern |
|---------|---------|
| Pack grid | `PackGrid(..., selectOnFocus = isTelevision, firstTileFocusRequester, onTileFocused)` |
| Initial focus | `LaunchedEffect(openedFamily)` / `LaunchedEffect(Unit)` → `FocusRequester.requestFocus()` |
| Buy CTA | Put `Modifier.focusRequester(buyFocus)` on the primary Button; re-request when selection changes |
| Paywall / Account | Full-screen `Scaffold` + vertical scroll; primary CTA gets initial focus on TV |
| Padding | Wider horizontal padding on TV (`48.dp`) vs phone (`16.dp`) |

Detect TV:

```kotlin
val isTelevision = LocalConfiguration.current.uiMode and Configuration.UI_MODE_TYPE_MASK ==
    Configuration.UI_MODE_TYPE_TELEVISION
```

## Focus checklist for a new TV screen

1. Identify the first interactive target (first tile, primary Buy, Restore).
2. `remember { FocusRequester() }` + `Modifier.focusRequester(...)`.
3. `LaunchedEffect(readyCondition) { requester.requestFocus() }`.
4. For lazy grids, only attach requesters to composed items; key items by stable id.
5. Optional `focusProperties { ... }` only when spatial search is wrong — prefer default D-pad search.
6. Back: `BackHandler` / navigation icon; do not consume unrelated keys.
7. Test with Direction keys + Center/Enter, not touch clicks alone.

## Billing / paywall on TV

- Wire real RevenueCat `purchaseProduct(activity, productId)` — Play Billing sheets work on TV when the device supports purchases.
- Show formatted price when `productPrices[productId]` is available.
- Always offer **Restore purchases** on Account and Paywall.
- Keep Premium (UX) and Marketplace packs as separate SKUs / entitlements.

## Related

- Compose focus details: `compose-focus-navigation` skill
- RevenueCat one-time packs: `rc-one-time-products`, `rc-purchase-flow`
