# geoking-tools

Scripts partagés pour les apps Android GeoKing (release Play, OAuth, adb, build local).

> **Nouvelle app ?** → **[INTEGRATION.md](INTEGRATION.md)** (guide pas-à-pas complet)

## Bootstrap rapide

Depuis la racine de ton app (sibling de `geoking-tools`) :

```bash
../geoking-tools/templates/bootstrap-new-app.sh --package fr.geoking.myapp --name MyApp
```

Crée `scripts/`, les wrappers, les workflows CI, `playstore/` minimal et les entrées `.gitignore`.

## Installation manuelle

Clone à côté de tes projets :

```
~/dev/android/
├── geoking-tools/
├── vincent/
└── scora/
```

Ou : `export GK_TOOLS=~/dev/android/geoking-tools`

Voir [INTEGRATION.md](INTEGRATION.md) pour le détail (manifest, Gradle, secrets, CI).

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
| `migrate-geoking-dns.sh` | Migration DNS Netlify → Cloudflare Pages (`geoking.fr`) |
| `cutover-cloudflare-dns.sh` | Phase 3 : zone Cloudflare DNS + domaines Pages + NS |

## Templates

| Fichier | Usage |
|---|---|
| `templates/bootstrap-new-app.sh` | Scaffold automatique dans une app |
| `templates/project.manifest.json` | Catalogue projets GeoKing (DNS, repos) |
| `templates/project.manifest.template.json` | Manifest exemple pour une nouvelle app |
| `templates/android-ci.yml` | Workflow CI debug |
| `templates/release-play.yml` | Workflow release Play |
| `INTEGRATION.md` | Guide d'intégration complet |

## DNS geoking.fr (Netlify → Cloudflare)

- **Projets** : `templates/project.manifest.json` (`dns.subdomain`, `dns.pagesProject`)
- **Référence Netlify** : `geoking.fr (DNS Records).csv` (export Netlify → cibles `*.netlify.app`, rollback)

Ré-exporter le CSV depuis Netlify après tout changement DNS manuel.

```bash
# Tokens lus depuis local.properties (NETLIFY_TOKEN, CLOUDFLARE_*)
./scripts/migrate-geoking-dns.sh reference
./scripts/migrate-geoking-dns.sh status
./scripts/migrate-geoking-dns.sh migrate --site vincent --dry-run
./scripts/migrate-geoking-dns.sh migrate --all --verify
```

### Phase 3 — Zone Cloudflare (avant/après cutover NS)

Prérequis : `geoking.fr` ajouté dans Cloudflare.

```bash
./scripts/cutover-cloudflare-dns.sh plan
./scripts/cutover-cloudflare-dns.sh apply-all --dry-run
./scripts/cutover-cloudflare-dns.sh nameservers
```

## DNS domaine externe (ex. scorawatch.com)

Pour un domaine **hors `geoking.fr`** (zone DNS propre, ex. `scorawatch.com` chez Namecheap), la migration vers Cloudflare Pages se fait en 3 temps. L'ancien hébergeur (Netlify) continue de servir le site tant que les NS ne sont pas basculés → **zéro downtime**.

1. **Créer la zone Cloudflare** :

```bash
curl -sS -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones" \
  -d "{\"name\":\"scorawatch.com\",\"account\":{\"id\":\"$CLOUDFLARE_ACCOUNT_ID\"},\"type\":\"full\"}"
```

2. **Répliquer le DNS** vers la zone via le script dédié, vivant dans le repo applicatif (`scora-landingpage/scripts/cutover-scorawatch-dns.sh`) :

```bash
cd ../scora-landingpage && ./scripts/cutover-scorawatch-dns.sh
```

Le script (idempotent) crée dans la zone : apex + `www` en **CNAME proxifié** vers `scora-landingpage.pages.dev` (CNAME flattening sur l'apex), les `MX` ImprovMX (`mx1`/`mx2`, prio 10/20), le `TXT` SPF (`v=spf1 include:spf.improvmx.com ~all`) et le `TXT` de vérif Google, puis affiche les **nameservers** de la zone.

3. **Basculer les NS chez le registrar** (Namecheap → Domain List → *Custom DNS*), en remplaçant `dns1/dns2.registrar-servers.com` par les NS affichés par le script, p. ex. :

```
adam.ns.cloudflare.com
sunny.ns.cloudflare.com
```

Les NS exacts sont propres à chaque zone (se fier à la sortie du script). Une fois propagés, la zone passe `active` et les domaines personnalisés du projet Pages s'activent automatiquement (certificat émis).

> **Permission token Cloudflare** : *créer* une zone exige **`Zone:Edit`** (groupe **Zone**, *pas* Account) avec **Zone Resources = All zones from an account**. C'est distinct de **`Zone → DNS → Edit`**, qui ne gère que les enregistrements de zones déjà existantes.

Le manifeste catalogue aussi ces sites à domaine externe (champs `domain`, `build`, `dns.zone`, `dns.apex`) :

```json
{
  "id": "scora-landingpage",
  "domain": "scorawatch.com",
  "build": { "command": "npm ci && npm run build", "output": "dist", "nodeVersion": "20" },
  "dns": { "zone": "scorawatch.com", "subdomain": "www", "apex": true, "pagesProject": "scora-landingpage" }
}
```

## CI

Workflows réutilisables dans **[geoking-ci](https://github.com/ludoo0d0a/geoking-ci)** — voir [INTEGRATION.md §6](INTEGRATION.md#6-github-actions-geoking-ci).
