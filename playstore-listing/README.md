# GeoKing Play listing tooling

Copied from Scora `scripts/playstore/`. Manage Play Console listings, listing translations, and screenshot validation.

```bash
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" --help
bash "$GK_TOOLS/playstore-listing/translate-listing.sh"
python3 "$GK_TOOLS/playstore-listing/validate_screenshots.py" --help
```

Install deps: `pip install -r "$GK_TOOLS/playstore-listing/requirements.txt"`
