# Play Console — service account app permissions

App-level permissions to grant a Google Cloud **service account**
(`…@….iam.gserviceaccount.com`) used by CI / scripts (store listing, AAB upload, what’s new).

> Path: Play Console → **Users and permissions** → SA user → select the app.
> You must be a developer-account **Admin** to change these.
> Propagation: minutes (sometimes up to 24–48h).

API reference: [`AppLevelPermission`](https://developers.google.com/android-publisher/api-ref/rest/v3/grants#applevelpermission).

French Console labels are included (Play Console UI locale).

## Recommended profiles

### Minimum — store listing

| Console UI (EN) | Console UI (FR) | API enum | Used for |
|-----------------|-----------------|----------|----------|
| View app information (read-only) | Afficher les informations sur l'application (lecture seule) | `CAN_VIEW_NON_FINANCIAL_DATA` | Required base |
| Manage store presence | Gérer la présence sur le Play Store | `CAN_MANAGE_PUBLIC_LISTING` | Listing texts, screenshots, feature graphic (`listing_cli upload`) |

### CI / what’s new — testing tracks

Add:

| Console UI (EN) | Console UI (FR) | API enum | Used for |
|-----------------|-----------------|----------|----------|
| Release apps to testing tracks | Déployer les applications sur des canaux de test | `CAN_MANAGE_TRACK_APKS` | Internal / alpha / beta / Wear test tracks; release notes; test AAB upload |

### Production (optional, sensitive)

Only if scripts/CI update **production** / form-factor production tracks:

| Console UI (EN) | Console UI (FR) | API enum | Used for |
|-----------------|-----------------|----------|----------|
| Release apps to production, exclude devices, and use Play App Signing | Mettre les applications à disposition de tous les utilisateurs, exclure des appareils et utiliser la signature d'application Play | `CAN_MANAGE_PUBLIC_APKS` | Production releases + production release notes |

## Do not enable (unless explicitly needed)

| Console UI (FR) | Why |
|-----------------|-----|
| Administrateur (toutes les autorisations) | Too broad; can invite other users |
| Afficher les informations sur la qualité… | Read-only Vitals |
| Créer et supprimer les versions provisoires d’applications | Draft apps only |
| Afficher les données financières | Finance |
| Gérer les commandes et les abonnements | Refunds / subscriptions |
| Gérer les canaux de test et modifier les listes de testeurs | Tester lists only |
| Répondre à des avis | Reviews |
| Gérer les déclarations de règle | Policy |
| Gérer les liens profonds | Deeplinks |

## Typical GeoKing checklist

- [x] View app information (read-only)
- [x] Manage store presence
- [x] Release apps to testing tracks
- [ ] Release apps to production… *(only if prod via API)*

Without **testing tracks** and/or **production** release permissions, `edits.tracks` + `edits.commit` for release notes often returns **403**.

## Related tooling

- Listing CLI: [`listing_cli.py`](./listing_cli.py)
- App integration: [`../INTEGRATION.md`](../INTEGRATION.md)
- Reusable Play upload workflow: [geoking-ci `release-play.yml`](https://github.com/ludoo0d0a/geoking-ci/blob/main/.github/workflows/release-play.yml)
- Scora-specific copy + Console links: [scora `doc/playstore/service-account-permissions.md`](https://github.com/ludoo0d0a/scora/blob/main/doc/playstore/service-account-permissions.md)
