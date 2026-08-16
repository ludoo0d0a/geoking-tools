# GeoKing translate (DeepL)

Copied from Scora `i18n/` as a shared reference implementation. **Do not edit Scora to become the package** — improve this tree, then apps wrap it.

## Use from an app

```bash
# From app root (sibling of geoking-tools):
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
# Point translate.py at your modules via CLI flags / app wrappers under scripts/
"$GK_TOOLS/translate/translate.sh"
```

Requires a `.env` with DeepL credentials (same as Scora). Adapt module list (`app`, `shared`, …) per project.
