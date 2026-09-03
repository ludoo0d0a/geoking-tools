#!/usr/bin/env python3
"""Play Console first-publish answers stored in scripts/project.manifest.json.

Per-app data lives in ``playConsole`` (this project). This script is the shared
pattern: validate, print a Console checklist, apply API-writable fields.

Usage (from the app repo root):

  python3 "$GK_TOOLS/playstore-listing/play_console.py" validate
  python3 "$GK_TOOLS/playstore-listing/play_console.py" checklist
  python3 "$GK_TOOLS/playstore-listing/play_console.py" apply-details --dry-run
  python3 "$GK_TOOLS/playstore-listing/play_console.py" apply-data-safety --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import listing_cli as listing  # noqa: E402

REQUIRED_PATHS: tuple[tuple[str, ...], ...] = (
    ("appType",),
    ("category",),
    ("defaultLanguage",),
    ("contact", "email"),
    ("contact", "website"),
    ("contact", "privacyPolicyUrl"),
    ("storeListing", "locales"),
    ("declarations", "governmentApp"),
    ("declarations", "financialFeatures"),
    ("declarations", "healthApp"),
    ("declarations", "containsAds"),
    ("declarations", "advertisingId", "usesAdvertisingId"),
    ("declarations", "signInRequired"),
    ("declarations", "targetAge"),
    ("declarations", "dataSafety", "csv"),
)

PLACEHOLDERS = {"", "TODO", "null", "CHANGE_ME"}


def repo_root() -> Path:
    env = os.environ.get("GK_PROJECT_ROOT")
    if env:
        return Path(env).resolve()
    cwd = Path.cwd().resolve()
    for candidate in (cwd, *cwd.parents):
        if (candidate / "scripts" / "project.manifest.json").is_file():
            return candidate
    return cwd


def load_manifest() -> dict[str, Any]:
    listing.REPO_ROOT = repo_root()
    listing.MANIFEST_PATH = listing.REPO_ROOT / "scripts" / "project.manifest.json"
    listing.DEFAULT_SA = listing.REPO_ROOT / "scripts" / ".play-service-account.json"
    data = listing.load_project_manifest()
    if not data:
        raise SystemExit(f"Missing {listing.MANIFEST_PATH}")
    return data


def play_console(manifest: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    m = manifest if manifest is not None else load_manifest()
    block = m.get("playConsole")
    if not isinstance(block, dict) or not block:
        raise SystemExit(
            "scripts/project.manifest.json is missing a non-empty playConsole object.\n"
            "Copy geoking-tools/templates/play-console.fragment.json and fill it."
        )
    return block


def _get(data: dict[str, Any], path: tuple[str, ...]) -> Any:
    cur: Any = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def _is_filled(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str) and value.strip() in PLACEHOLDERS:
        return False
    if isinstance(value, list) and not value:
        return False
    return True


def cmd_validate(_args: argparse.Namespace) -> int:
    root = repo_root()
    pc = play_console()
    errors: list[str] = []
    for path in REQUIRED_PATHS:
        dotted = ".".join(path)
        value = _get(pc, path)
        if not _is_filled(value):
            errors.append(f"playConsole.{dotted} is missing")
    csv_rel = _get(pc, ("declarations", "dataSafety", "csv"))
    if isinstance(csv_rel, str) and csv_rel.strip() not in PLACEHOLDERS:
        csv_path = root / csv_rel
        if not csv_path.is_file():
            errors.append(f"data safety CSV not found: {csv_rel}")
    if errors:
        print("playConsole validation failed:")
        for err in errors:
            print(f"  - {err}")
        return 1
    print(f"✅ playConsole OK ({listing.package_name()})")
    return 0


def cmd_checklist(_args: argparse.Namespace) -> int:
    pc = play_console()
    contact = pc.get("contact") or {}
    listing_block = pc.get("storeListing") or {}
    dist = pc.get("distribution") or {}
    decl = pc.get("declarations") or {}
    ads = decl.get("advertisingId") or {}
    safety = decl.get("dataSafety") or {}
    rating = decl.get("contentRating") or {}
    fgs = decl.get("foregroundServices") or {}
    release = pc.get("release") or {}
    internal = dist.get("internalTesting") or {}

    def yn(v: Any) -> str:
        if v is True:
            return "Yes"
        if v is False:
            return "No"
        return str(v)

    lines = [
        f"Package: {listing.package_name()}",
        f"App type: {pc.get('appType')}",
        f"Category: {pc.get('category')}",
        f"Default language: {pc.get('defaultLanguage')}",
        "",
        "Contact",
        f"  Email: {contact.get('email')}",
        f"  Website: {contact.get('website')}",
        f"  Privacy policy (Play): {contact.get('privacyPolicyUrl')}",
        "",
        "Store listing",
        f"  Locales: {', '.join(listing_block.get('locales') or [])}",
        f"  Icon: {listing_block.get('icon')}",
        f"  Feature graphic: {listing_block.get('featureGraphic')}",
        f"  Listings dir: {listing_block.get('listingsDir')}",
        "",
        "Distribution",
        f"  Countries: {', '.join(dist.get('countries') or [])}",
        f"  Managed publishing: {yn(dist.get('managedPublishing'))}",
        f"  Internal testers list: {internal.get('testersListName')}",
        f"  Internal opt-in: {internal.get('optInUrl')}",
        "",
        "Declarations (Play Console → App content)",
        f"  Government app: {yn(decl.get('governmentApp'))}",
        f"  Financial features: {yn(decl.get('financialFeatures'))}",
        f"  Health app: {yn(decl.get('healthApp'))}",
        f"  Contains ads: {yn(decl.get('containsAds'))}",
        f"  Advertising ID used: {yn(ads.get('usesAdvertisingId'))}",
        f"  Advertising ID purposes: {', '.join(ads.get('purposes') or [])}",
        f"  Sign-in required: {yn(decl.get('signInRequired'))}",
        f"  All features without restriction: {yn(decl.get('allFeaturesAvailableWithoutRestriction'))}",
        f"  Target age: {decl.get('targetAge')}",
        f"  IARC category: {rating.get('questionnaireCategory')}",
        f"  IARC notes: {rating.get('notes')}",
        f"  FGS mediaPlayback: {yn(fgs.get('mediaPlayback'))}",
        "",
        "Data safety",
        f"  CSV: {safety.get('csv')}",
        f"  Collects or shares: {yn(safety.get('collectsOrShares'))}",
        f"  Encrypted in transit: {yn(safety.get('encryptedInTransit'))}",
        f"  In-app accounts: {yn(safety.get('inAppAccounts'))}",
        f"  Outside-app accounts: {yn(safety.get('outsideAppAccounts'))}",
        f"  User data deletion offered: {yn(safety.get('userDataDeletion'))}",
        f"  Data types: {', '.join(safety.get('dataTypes') or [])}",
        "",
        "Release snapshot",
        f"  Production: {release.get('productionVersionName')} "
        f"(versionCode {release.get('productionVersionCode')})",
    ]
    print("\n".join(lines))
    return 0


def _details_body(pc: dict[str, Any]) -> dict[str, str]:
    contact = pc.get("contact") or {}
    body: dict[str, str] = {}
    if pc.get("defaultLanguage"):
        body["defaultLanguage"] = str(pc["defaultLanguage"])
    if contact.get("email"):
        body["contactEmail"] = str(contact["email"])
    if contact.get("website"):
        body["contactWebsite"] = str(contact["website"])
    return body


def cmd_apply_details(args: argparse.Namespace) -> int:
    if cmd_validate(args) != 0:
        return 1
    pc = play_console()
    body = _details_body(pc)
    privacy = (pc.get("contact") or {}).get("privacyPolicyUrl")
    package = listing.package_name()
    print(f"📦 {package}")
    print(f"   details patch: {json.dumps(body, ensure_ascii=False)}")
    if privacy:
        print(f"   privacyPolicyUrl (Console field; set via details if API accepts it): {privacy}")
    if args.dry_run:
        print("🧪 Dry-run — no Play API call.")
        return 0
    service = listing.build_publisher_service()
    edit = service.edits().insert(packageName=package, body={}).execute()
    edit_id = edit["id"]
    patch = dict(body)
    if privacy:
        patch["privacyPolicyUrl"] = str(privacy)
    try:
        service.edits().details().patch(
            packageName=package, editId=edit_id, body=patch
        ).execute()
        listing.commit_edit(service, package, edit_id, draft=True)
        print("✅ App details committed (draft).")
        return 0
    except Exception as e:
        try:
            service.edits().delete(packageName=package, editId=edit_id).execute()
        except Exception:
            pass
        print(f"❌ apply-details failed: {listing._http_error_message(e)}")
        return 1


def cmd_apply_data_safety(args: argparse.Namespace) -> int:
    if cmd_validate(args) != 0:
        return 1
    root = repo_root()
    pc = play_console()
    csv_rel = str(_get(pc, ("declarations", "dataSafety", "csv")))
    csv_path = root / csv_rel
    csv_text = csv_path.read_text(encoding="utf-8")
    package = listing.package_name()
    print(f"📦 {package}")
    print(f"   CSV: {csv_rel} ({len(csv_text)} chars)")
    if args.dry_run:
        print("🧪 Dry-run — no Play API call.")
        return 0
    service = listing.build_publisher_service()
    service.applications().dataSafety(
        packageName=package, body={"safetyLabels": csv_text}
    ).execute()
    print("✅ Data safety CSV uploaded.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate / print / apply Play Console answers from playConsole"
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate", help="Check required playConsole fields + CSV path").set_defaults(
        func=cmd_validate
    )
    sub.add_parser("checklist", help="Print Console answers for the next app").set_defaults(
        func=cmd_checklist
    )
    details = sub.add_parser(
        "apply-details",
        help="PATCH defaultLanguage / contact via Publisher API",
    )
    details.add_argument("--dry-run", action="store_true")
    details.set_defaults(func=cmd_apply_details)
    safety = sub.add_parser(
        "apply-data-safety",
        help="Upload declarations.dataSafety.csv via applications.dataSafety",
    )
    safety.add_argument("--dry-run", action="store_true")
    safety.set_defaults(func=cmd_apply_data_safety)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
