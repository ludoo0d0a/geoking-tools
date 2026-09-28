# GeoKing Play listing tooling

Copied from Scora `scripts/playstore/`. Manage Play Console listings, listing translations, screenshot validation, and first-publish answers.

```bash
# Preferred (after link-scripts.sh):
./scripts/listing-cli.sh --help
./scripts/play-console.sh validate
./scripts/play-console.sh checklist

# Or call the tools tree directly:
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" --help
bash "$GK_TOOLS/playstore-listing/translate-listing.sh"
python3 "$GK_TOOLS/playstore-listing/validate_screenshots.py" --help
```

## First-publish answers (`playConsole`)

Store Console questionnaires in the **app** repo: `scripts/project.manifest.json` → `playConsole`.

Preferred (skill **gk-project-manifest**):

```bash
./scripts/project-manifest.sh init --package fr.geoking.myapp --name MyApp
./scripts/project-manifest.sh merge-play-console   # if playConsole missing
./scripts/project-manifest.sh set .playConsole.contact.email hello@geoking.fr
./scripts/project-manifest.sh validate
./scripts/play-console.sh validate
./scripts/play-console.sh checklist
```

Skeleton: [`templates/play-console.fragment.json`](../templates/play-console.fragment.json).  
Data safety CSV: `scripts/playstore/data_safety.csv`.

Arthur is the filled reference. For a new app:

1. Ensure `playConsole` via `project-manifest.sh` (init / merge-play-console) and replace TODOs.
2. Copy/adapt `data_safety.csv`.
3. `./scripts/play-console.sh validate` then `checklist` while filling Play Console.
4. Optional API: `apply-details` / `apply-data-safety` (needs Play SA). Government, health, IARC, ads ID purposes, and FGS still need the Console UI.

Install deps: `pip install -r "$GK_TOOLS/playstore-listing/requirements.txt"`

## Service account permissions

Play Console checkboxes for listing + CI release (FR/EN + API enums):

→ [`service-account-permissions.md`](./service-account-permissions.md)
