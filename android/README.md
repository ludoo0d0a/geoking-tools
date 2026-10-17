# geoking-tools Android libraries

Consumed by GeoKing apps via **same-build `include` + `projectDir`** (not `includeBuild`).
Composite `includeBuild` breaks Android Studio sync for these Android library modules
(`Expected android module not found! … Path: :debug-bar`) while CLI Gradle still works.

This directory remains a standalone Gradle build for library-only CI.

| Module | App project path | Role |
|---|---|---|
| `debug-bar/` | `:debug-bar` | Floating bug FAB + network/provider/data-usage overlay |
| `in-app-update/` | `:in-app-update` | Play flexible In-App Updates helper + update-available notification (tap → start update) |

See [`skills/gk-debug-bar/SKILL.md`](../skills/gk-debug-bar/SKILL.md) and
[`skills/gk-play-in-app-updates/SKILL.md`](../skills/gk-play-in-app-updates/SKILL.md).
