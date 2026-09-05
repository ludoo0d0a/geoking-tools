---
name: gk-i18n
description: >-
  Wire Scora-style Android string i18n (DeepL forward/back translate, glossary,
  roundtrip compare, cleanup) for a GeoKing app. Use when adding translations,
  values-*/strings.xml, DeepL, i18n/, translate.sh, roundtrip, glossary,
  gk-i18n, or polishing locales before release.
---

# App string i18n (Scora pattern)

Success = English source in `values/strings.xml`, target locales under
`values-{lang}/`, DeepL forward-fill via app-local `i18n/`, optional glossary
bias, roundtrip QA, unused-string cleanup. Shared scripts live in
**geoking-tools/translate/**; each app keeps an **`i18n/`** tree (Scora layout).

| Reference | Role |
|---|---|
| **Scora** (`~/dev/android/scora/i18n`) | Canonical full pipeline — use this |
| **geoking-tools/translate/** | Shared copy to bootstrap / improve (do not refactor Scora in place) |
| **Gaston** | Minimal locales (`values` + `values-fr`) — fine for phone-only GeoKing until more langs are needed |

Resolve tools: sibling `../geoking-tools` or `$GK_TOOLS`. This skill lives in
`geoking-tools/skills/gk-i18n/`.

```
~/dev/android/
├── geoking-tools/translate/     # shared scripts (source of truth to copy from)
└── <app>/
    ├── app/ (or androidApp/) …/res/values/strings.xml      # EN source
    ├── app/…/res/values-{lang}/strings.xml
    ├── shared/…/res/…                                      # if multi-module
    └── i18n/
        ├── .env                 # DEEPL_API_KEY (gitignored)
        ├── languages.py         # SUPPORTED_LOCALES for this app
        ├── glossary/{lang}.md   # optional DeepL context
        ├── translate.py         # from geoking-tools (or Scora)
        ├── translate.sh
        ├── backtranslate.sh
        ├── compare.sh / compare_roundtrip.py
        ├── cleanup.sh / remove_unused_strings.py
        └── draft/…              # back-translation drafts (generated)
```

`translate.py` resolves `PROJECT_ROOT` as **parent of `i18n/`**. Scripts must
live under **`<app>/i18n/`** (copy from geoking-tools). Do **not** run them
from the geoking-tools tree — paths would point at the tools repo.

## Progress checklist

```
- [ ] 1. Bootstrap <app>/i18n/ from geoking-tools/translate (+ .gitignore .env)
- [ ] 2. languages.py: SUPPORTED_LOCALES (+ Play map) for this product
- [ ] 3. Sync Gradle resource locales / supportedLocales if the app filters langs
- [ ] 4. i18n/.env with DEEPL_API_KEY (never commit)
- [ ] 5. Optional glossary/{lang}.md for domain terms
- [ ] 6. Thin wrappers: translate.sh / backtranslate.sh (--modules for this app)
- [ ] 7. Forward-translate missing strings; spot-check FR (and others)
- [ ] 8. Optional: backtranslate + compare.sh --html QA
- [ ] 9. Optional: cleanup.sh --dry-run before deleting unused keys
```

## Default decisions

| Choice | Default | Notes |
|---|---|---|
| Source | `values/strings.xml` (English) | No `values-en` required as source |
| Provider | **DeepL** | LibreTranslate via `--provider libre` if needed |
| Merge | Missing keys only | `--overwrite` / `--keys` only when intentional |
| Modules | Match the app | Scora: `app shared wear`; Gaston-like: `androidApp` or `app` |
| Min locales (new GeoKing phone) | **en + fr** | Expand when product asks |
| Glossary | Optional | Scora tennis glossary is product-specific — do not copy into unrelated apps |
| Play listing translate | Separate | `geoking-tools/playstore-listing` reuses DeepL helpers; see INTEGRATION.md |

---

## 1. Bootstrap `i18n/`

From the app root:

```bash
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
mkdir -p i18n
cp -R "$GK_TOOLS/translate/"* i18n/
# Keep app-local secrets + drafts out of git
echo 'i18n/.env' >> .gitignore
echo 'i18n/draft/' >> .gitignore
echo 'i18n/roundtrip_report.html' >> .gitignore
```

Customize:

- `i18n/languages.py` — set `SUPPORTED_LOCALES` / `LANG_TO_PLAY_LOCALE` for **this** app
- `i18n/translate.sh` / `backtranslate.sh` — `--modules` list (drop `wear` if none)
- `i18n/glossary/` — delete Scora tennis files unless this product needs a domain glossary; add `{lang}.md` with `<!-- deepl:context:start -->` … `<!-- deepl:context:end -->` when you do

Module directory names must match Gradle module folders that contain
`src/main/res/values/strings.xml` (Scora: `app`, `shared`, `wear`).

---

## 2. Credentials

`i18n/.env` (or export in the shell):

```bash
DEEPL_API_KEY=…
# Optional paid endpoint:
# DEEPL_API_ENDPOINT=https://api.deepl.com
```

`translate.sh` does `source .env`. Never commit `.env`.

---

## 3. Day-to-day workflow

```bash
cd i18n

# Fill missing translations (EN values/ → values-{lang}/)
./translate.sh
# or:
python3 translate.py --mode forward --modules app shared --batch-size 25
python3 translate.py --mode forward --modules app --languages fr --keys my_new_key

# QA roundtrip (optional, Scora release polish)
./backtranslate.sh
./compare.sh --modules app shared --use-draft --html
./open_report.sh

# Remove unused keys (preview first)
./cleanup.sh --dry-run
./cleanup.sh --modules app
```

**Authoring rules**

1. Add / edit copy in **English** `values/strings.xml` (and shared modules if split).
2. Run forward translate — do not hand-maintain dozens of locales.
3. Domain terms: add glossary entries **before** re-translating those keys (`--keys`).
4. Keep the same key wording across modules when the string is shared.
5. Preserve Android placeholders (`%1$s`, `%d`, `%%`) and `\n`.
6. `translatable="false"` stays only in default `values/`.

---

## 4. Scora release polish (optional)

Scora `./scripts/polish-release.sh` runs i18n then screenshots / website / Play pack.
`--skip-i18n` skips DeepL stages. New GeoKing apps can add a thinner script later;
do not copy Scora’s tennis-specific website/listing steps blindly.

---

## 5. Languages table

`languages.py` is the Python single source for tooling:

| Symbol | Role |
|---|---|
| `SUPPORTED_LOCALES` | App langs (keep in sync with Gradle locale filters) |
| `LANG_TO_PLAY_LOCALE` | App lang → Play Console BCP-47 |
| `DEEPL_SUPPORTED` | Full DeepL catalog (superset) |
| `deepl_code(lang)` | App/BCP-47 → DeepL code |

When adding a language: update `languages.py`, ensure `values-{lang}/` after
forward translate, and align Play listing / screenshot locales if those pipelines exist.

---

## 6. Glossary format (when needed)

```markdown
# Glossary — French (fr)

<!-- deepl:context:start -->
fuel station = station-service (NEVER "poste à essence" if product standard is X)
EV = VE
<!-- deepl:context:end -->
```

Loaded automatically as DeepL `context` for that target language.

---

## Verify

- New EN key appears in `values-fr/strings.xml` (and other targets) after forward translate
- Placeholders intact in translated files
- `compare.sh --html` opens without path errors (modules exist)
- `i18n/.env` not tracked by git

## Agent rules

- Prefer **copy into `<app>/i18n/`** from geoking-tools; improve shared scripts in geoking-tools, then re-copy or cherry-pick — do not make Scora the packaging root.
- Do not invent bulk human translations when DeepL is configured.
- Do not copy Scora tennis glossary / loanword rules into unrelated apps.
- Minimum for new phone apps: **EN + FR**; full Scora locale set only when product asks.
- Play Store listing / whatsnew translation is **related but separate** (`playstore-listing/`, app `whatsnew.py`) — wire after strings i18n exists.
