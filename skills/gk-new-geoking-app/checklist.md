# New GeoKing app — operator checklist

Use with the `gk-new-geoking-app` skill. Tick in order.

## Identity

- [ ] Name: _______________
- [ ] Package: `fr.geoking.________`
- [ ] Repo: `ludoo0d0a/________`
- [ ] Module: `:androidApp` / `:composeApp`
- [ ] Ship bar: internal only □  / production review □

## Local + GitHub

- [ ] Project builds (`assembleDebug`)
- [ ] `bootstrap-new-app.sh` run
- [ ] `./scripts/project-manifest.sh apply` (IDs) + `validate` ; `playConsole` TODOs replaced
- [ ] Workflows: `package_name`, `artifact_name`, module globs
- [ ] Gradle: JDK 21, signing env, VERSION_* from playstore/
- [ ] `gh repo create` + push `main`
- [ ] `geoking-ci` public on GitHub

## Firebase / secrets

- [ ] Firebase Android app created
- [ ] `./scripts/pull-google-services.sh --push`
- [ ] `./scripts/setup-release.sh` (keystore + Play SA + verify)
- [ ] `./scripts/show-secrets.sh` — all required secrets on GitHub
- [ ] SHA-1: debug + upload (+ Play App Signing after first AAB)

## Play Console

- [ ] App created; `./scripts/project-manifest.sh apply --play-developer-id … --play-app-id …`
- [ ] `./scripts/play-console.sh validate` + `checklist`
- [ ] Listing EN (+ FR); icon 512; feature graphic
- [ ] Screenshots validated
- [ ] Data safety CSV uploaded / Console Traitée
- [ ] Ads ID / IARC / target age / gov-finance-health done
- [ ] Countries set (e.g. FR)

## CI / tracks

- [ ] `release-play` → internal **completed** (unit tests run in this workflow)
- [ ] `android-ci` optional via `workflow_dispatch` (not required on `main`)
- [ ] Testers list + opt-in URL works
- [ ] Production left **draft** (unless public requested)
- [ ] `playConsole.release.tracks` updated in manifest
