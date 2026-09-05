---
name: gk-website-sync
description: >-
  Keep a GeoKing Android app's website/ in the monorepo in sync with Roborazzi
  screenshots and deploy it via Cloudflare CI (Scora pattern). Use when wiring
  or updating arthur.geoking.fr-style landings, fill_website_screenshots,
  screenshot-sources.json, website-screenshots / website-deploy workflows,
  gk-website-sync / website-sync, or when asked to sync website from the main
  app inside the monorepo.
---

# Website sync (monorepo → Cloudflare)

Canonical pattern (reference: **Scora** full pipeline; **Arthur** / **Vincent** for static GeoKing landings):

1. Landing lives in **`website/` inside the Android app repo** (not a separate landing repo).
2. Roborazzi (or Play montages) produce PNGs under `screenshots/`.
3. **`fill_website_screenshots.py`** (geoking-tools) copies them into `website/assets/` per `website/screenshot-sources.json`.
4. GitHub Actions: regenerate + commit assets; deploy `website/` to Cloudflare.

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`.

```
~/dev/android/
├── geoking-tools/
├── geoking-ci/
└── <app>/
    ├── screenshots/          # Roborazzi outputs
    ├── website/              # published tree
    │   ├── index.html
    │   ├── screenshot-sources.json
    │   └── assets/screenshots/{lang}/
    ├── scripts/fill_website_screenshots.py   # thin wrapper → geoking-tools
    └── .github/workflows/
        ├── website-screenshots.yml
        └── website-deploy.yml   # or cloudflare-pages.yml
```

## Progress checklist

```
- [ ] 1. website/ landing + privacy (static HTML; no npm unless Scora-class)
- [ ] 2. website/screenshot-sources.json (copies map)
- [ ] 3. scripts/fill_website_screenshots.py wrapper + root Gradle generateWebsiteScreenshots
- [ ] 4. Sync once locally; commit website/assets
- [ ] 5. CI: website-screenshots.yml + deploy workflow (Workers or Pages)
- [ ] 6. Secrets CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID
- [ ] 7. DNS / custom domain (manifest dns.* + cutover scripts if needed)
```

## 1. screenshot-sources.json

Minimal GeoKing shape:

```json
{
  "locales": ["en", "fr"],
  "copies": [
    {
      "from": "screenshots/phone/framed/{locale}",
      "to": "website/assets/screenshots/{locale}",
      "glob": "*.png"
    },
    {
      "from": "screenshots/phone/montages/{locale}",
      "to": "website/assets/montages/{locale}",
      "glob": "*.png"
    }
  ]
}
```

Placeholders: `{locale}` or `{lang}`. Optional per-copy `"required": ["ambient.png", …]` fails the sync if missing.

Legacy keys `phoneDir` / `phoneMontagesDir` still work (Arthur early config).

## 2. Fill script (shared)

```bash
# From app root
./scripts/fill_website_screenshots.py
./scripts/fill_website_screenshots.py --locales en,fr --dry-run
```

Wrapper:

```bash
# scripts/fill_website_screenshots.py
#!/usr/bin/env bash
export GK_SCRIPT=fill_website_screenshots.py
exec "$(cd "$(dirname "$0")" && pwd)/_geoking-wrapper.sh" "$@"
```

Or call `$GK_TOOLS/bin/fill_website_screenshots.py` directly. Logic lives only in geoking-tools — do **not** fork a second copy per app (Scora’s older app-local script is the historical exception).

## 3. Gradle (root `build.gradle.kts`)

Wire generation → fill. Adjust module tasks to the app:

```kotlin
tasks.register<Exec>("copyWebsiteScreenshots") {
    group = "website"
    workingDir = rootDir
    commandLine("python3", "scripts/fill_website_screenshots.py")
}

tasks.register("generateWebsiteScreenshots") {
    group = "screenshots"
    description = "Roborazzi phone shots + copy into website/assets"
    dependsOn(":androidApp:generatePhoneScreenshotsFramed")
    // Optional: also :androidApp:generatePhoneScreenshots
    finalizedBy("copyWebsiteScreenshots")
}
```

**Scora** also generates wear faces + runs `npm run preview` for mockups/GIFs — keep that app-specific; GeoKing static sites stop at PNG copy.

## 4. Landing content rules

- Source of truth for product copy: Play listing (`doc/playstore/listings/…`) + `CONTEXT.md` / README — factual only.
- Hero uses **real** synced screenshots under `website/assets/…`, not CDN placeholders.
- Prefer static `index.html` (Vincent / Arthur). Add npm/i18n/mockups only when the product needs Scora-level motion assets.
- Privacy URL must match Play / `project.manifest.json` `urls.website.policy`.

## 5. Cloudflare deploy mode

| Mode | When | Template | Config |
|---|---|---|---|
| **Workers assets** | `wrangler.jsonc` + `assets.directory` / `dns.workerCustomDomain` | `templates/website-deploy-workers.yml` | Arthur |
| **Pages** | `wrangler.toml` `pages_build_output_dir` / `dns.pagesProject` | `templates/cloudflare-pages.yml` | Vincent-style |

Copy the matching template into `.github/workflows/website-deploy.yml` (or keep an existing `cloudflare-pages.yml` name — either is fine if paths match).

Required secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

DNS helpers already in geoking-tools: `migrate-geoking-dns.sh`, `cutover-cloudflare-dns.sh`, catalogue in `templates/project.manifest.json`.

## 6. CI — screenshots workflow

Copy `templates/website-screenshots.yml` → `.github/workflows/website-screenshots.yml`.

Triggers: `workflow_dispatch`, weekly schedule, push paths that affect previews / fill config. Job runs `./gradlew generateWebsiteScreenshots` then commits `website/assets` if dirty.

Needs `permissions: contents: write` (and a token that can push to `main`, or adjust to open a PR).

## 7. Local verify

```bash
./gradlew generateWebsiteScreenshots -PscreenshotLocales=en,fr
# or copy-only if PNGs already exist:
./scripts/fill_website_screenshots.py
test -f website/assets/screenshots/en/ambient.png   # adjust names
npx wrangler deploy   # or pages deploy — dry-run with wrangler whoami first
```

## Guardrails

- Do not invent metrics, store links, or screenshots.
- Private GitHub repos: no public GitHub CTA on the landing (same rule as portfolio-sync).
- Do not move Scora’s npm mockup/GIF pipeline into geoking-tools; only the **copy map** is shared.
- Keep deploy secrets in GitHub / `local.properties` — never commit tokens.

## Related

- Skill **gk-ci** — Play / android-ci wiring
- Skill **gk-new-geoking-app** — greenfield (bootstrap already copies Pages template)
- Scora: `website/README.md`, `scripts/fill_website_screenshots.py` (richer, wear+npm)
- Arthur: reference static Workers landing + this skill’s first consumer
