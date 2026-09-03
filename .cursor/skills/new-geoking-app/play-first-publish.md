# Play Console first-publish (GeoKing)

Companion to `new-geoking-app`. Store durable answers in the app’s  
`scripts/project.manifest.json` → `playConsole` (see `templates/play-console.fragment.json`).  
Arthur is the filled reference.

## Order that unblocks “Send for review”

1. **Store presence** — title, short/full description, icon 512, feature graphic, screenshots.
2. **Contact** — email, website, privacy policy URL (Play field often without `.html`).
3. **Category** + app type (Application vs Game).
4. **App content** — government / finance / health = usually No for GeoKing utilities.
5. **Ads declaration** — contains ads? (usually No).
6. **Advertising ID** — if merged `AD_ID` (Firebase Analytics), answer **Yes** + purpose **Analytics**; else remove permission and answer No.
7. **Sign-in / target age** — declare honestly; 18+ if needed.
8. **IARC** content rating questionnaire.
9. **Data safety** — CSV via `play_console.py apply-data-safety` or Console import; walk UI steps 1–5 after API write.
10. **Countries** — at least one (e.g. France).
11. **Internal** track completed + testers; **production** may stay draft.
12. Publishing overview → send changes when Send is enabled.

## Automation

```bash
export GK_TOOLS="${GK_TOOLS:-../geoking-tools}"
python3 "$GK_TOOLS/playstore-listing/play_console.py" validate
python3 "$GK_TOOLS/playstore-listing/play_console.py" checklist
python3 "$GK_TOOLS/playstore-listing/play_console.py" apply-details --dry-run
python3 "$GK_TOOLS/playstore-listing/play_console.py" apply-data-safety --dry-run
python3 "$GK_TOOLS/playstore-listing/listing_cli.py" links
```

Still Console-only: IARC questionnaire UI, many declaration radios, FGS demo video when you actually use a foreground service type.

## Pitfalls

| Symptom | Fix |
|---|---|
| Send disabled + ads ID incomplete | Manifest has `AD_ID` but form says Non → Yes + Analytics |
| Send locked “suivez le tableau de bord” | Finish production checklist rows (countries, preview) |
| CI upload 403 | Play SA missing testing/production or listing permission |
| Duplicate versionCode | Play already has that code; bump `github.run_number` / next run |
| FGS mediaPlayback demanded | Don’t declare unused FGS; remove permission until real playback |
| Data safety UI empty after API | Reload; walk steps 1–5 and save |

## Default GeoKing ship policy

- **Internal** = completed (testers can install).
- **Production** = draft until explicit “publish / send for review”.
- Record both under `playConsole.release.tracks`.
