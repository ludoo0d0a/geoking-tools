# geoking-tools

Scripts partagés pour les apps Android GeoKing (release Play, OAuth, adb, build local).

## Installation

Clone à côté de tes projets :

```
~/dev/android/
├── geoking-tools/
├── vincent/
└── scora/
```

Ou exporte le chemin :

```bash
export GEOKING_TOOLS=~/dev/android/geoking-tools
```

## Intégration dans un projet

1. Copie `templates/project.manifest.json` → `scripts/project.manifest.json` et remplis les IDs/URLs.
2. Copie les wrappers depuis `templates/script-wrapper.sh` pour chaque script, ou symlink :

```bash
for s in setup-release show-secrets verify-oauth gen-keystore build-aab deploy-device adb-reconnect; do
  cp templates/script-wrapper.sh "scripts/$s.sh"
done
chmod +x scripts/*.sh
```

3. Ajoute au `.gitignore` du projet :

```
scripts/.keystore-credentials
scripts/.adb-wireless
```

## Scripts

| Script | Rôle |
|---|---|
| `setup-release.sh` | Assistant release (keystore, Play, Firebase, OAuth, Gemini) |
| `show-secrets.sh` | Récap secrets locaux vs GitHub |
| `verify-oauth.sh` | Vérif Google Sign-In / SHA-1 |
| `gen-keystore.sh` | Génère release.keystore |
| `build-aab.sh` | Build AAB signé local + vérif empreinte |
| `deploy-device.sh` | Build APK + install sur appareil |
| `adb-reconnect.sh` | Boucle reconnexion adb sans fil |
| `whatsnew.py` | Génère `playstore/whatsnew/` depuis `whatsnew.xml` |

## Manifest

`scripts/project.manifest.json` est la source de vérité par projet (package, URLs consoles, module Gradle, activité de lancement). Chargé automatiquement via `lib/manifest.sh`.

## CI

Les workflows GitHub Actions vivent dans le dépôt sibling **[geoking-ci](../geoking-ci)**.
