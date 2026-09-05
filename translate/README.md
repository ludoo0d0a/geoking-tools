# GeoKing translate (DeepL)

Copied from Scora `i18n/` as a shared reference implementation. **Do not edit Scora to become the package** — improve this tree, then apps copy into their own `i18n/`.

**Skill:** [`../skills/gk-i18n/SKILL.md`](../skills/gk-i18n/SKILL.md)

## Use from an app

`translate.py` treats **parent of `i18n/`** as the Android project root. Copy (do not run in-place from geoking-tools):

```bash
# From app root (sibling of geoking-tools):
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
mkdir -p i18n && cp -R "$GK_TOOLS/translate/"* i18n/
# Edit i18n/languages.py + translate.sh --modules, add i18n/.env (DEEPL_API_KEY)
cd i18n && ./translate.sh
```

Requires a `.env` with DeepL credentials (same as Scora). Adapt module list (`app`, `shared`, …) per project.
