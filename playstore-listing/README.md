# GeoKing Play listing tooling

Copied from Scora `scripts/playstore/`. Manage Play Console listings, listing translations, screenshot validation, and first-publish answers.

```bash
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" --help
bash "$GK_TOOLS/playstore-listing/translate-listing.sh"
python3 "$GK_TOOLS/playstore-listing/validate_screenshots.py" --help
python3 "$GK_TOOLS/playstore-listing/play_console.py" validate
python3 "$GK_TOOLS/playstore-listing/play_console.py" checklist
```

## First-publish answers (`playConsole`)

Store Console questionnaires in the **app** repo: `scripts/project.manifest.json` → `playConsole`.
Copy the skeleton from [`templates/play-console.fragment.json`](../templates/play-console.fragment.json).
Put the Data safety CSV next to listing copy: `scripts/playstore/data_safety.csv`.

Arthur is the filled reference. For a new app:

1. Copy `playConsole` from the fragment (or from Arthur) and replace TODOs.
2. Copy/adapt `data_safety.csv`.
3. `play_console.py validate` then `checklist` while filling Play Console.
4. Optional API: `apply-details` / `apply-data-safety` (needs Play SA). Government, health, IARC, ads ID purposes, and FGS still need the Console UI.

Install deps: `pip install -r "$GK_TOOLS/playstore-listing/requirements.txt"`

## Service account permissions

Play Console checkboxes for listing + CI release (FR/EN + API enums):

→ [`service-account-permissions.md`](./service-account-permissions.md)
