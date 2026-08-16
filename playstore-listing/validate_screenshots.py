#!/usr/bin/env python3
"""Validate Play Store Wear/phone screenshots against screenshot-guidelines.md."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
GUIDE = REPO / "doc" / "playstore" / "screenshot-guidelines.md"

WEAR_MIN = 384
WEAR_MAX = 3840
PHONE_MIN = 320
PHONE_MAX = 3840
MAX_BYTES = 8 * 1024 * 1024
PHONE_PROMO_MIN = 1080


def _ratio_ok_phone(w: int, h: int, tol: float = 0.05) -> bool:
    r = w / h
    return abs(r - 16 / 9) <= tol or abs(r - 9 / 16) <= tol


def check_wear(path: Path) -> list[str]:
    issues: list[str] = []
    with Image.open(path) as im:
        w, h = im.size
        if w != h:
            issues.append(f"not 1:1 ({w}x{h})")
        if min(w, h) < WEAR_MIN or max(w, h) > WEAR_MAX:
            issues.append(f"side out of [{WEAR_MIN},{WEAR_MAX}] ({w}x{h})")
        if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
            # Reject any alpha channel (Play: no transparency)
            if im.mode == "RGBA":
                alpha = im.getchannel("A")
                if alpha.getextrema()[0] < 255:
                    issues.append("has transparency (alpha < 255)")
            else:
                issues.append(f"mode {im.mode} may include transparency")
        if path.stat().st_size > MAX_BYTES:
            issues.append("> 8 MiB")
    # Path heuristic: marketing filenames must not land in wear packs
        name = path.name.lower()
        if name.startswith("01_hero") or "live_score" in name:
            issues.append("looks like marketing montage (not WO-G5 UI-only)")
    return issues


def check_phone(path: Path) -> list[str]:
    issues: list[str] = []
    with Image.open(path) as im:
        w, h = im.size
        if not _ratio_ok_phone(w, h):
            issues.append(f"not 16:9/9:16 ({w}x{h})")
        if min(w, h) < PHONE_MIN or max(w, h) > PHONE_MAX:
            issues.append(f"side out of [{PHONE_MIN},{PHONE_MAX}] ({w}x{h})")
        if path.stat().st_size > MAX_BYTES:
            issues.append("> 8 MiB")
    return issues


def promo_phone_ok(paths: list[Path]) -> bool:
    """≥4 images with a side ≥1080."""
    count = 0
    for path in paths:
        with Image.open(path) as im:
            if max(im.size) >= PHONE_PROMO_MIN:
                count += 1
    return count >= 4


def audit_dir(wear_dir: Path | None, phone_dir: Path | None, label: str) -> int:
    errors = 0
    print(f"\n## {label}")
    if wear_dir and wear_dir.is_dir():
        wears = sorted(
            p
            for p in wear_dir.iterdir()
            if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
        )
        print(f"Wear count: {len(wears)} (need 1–8)")
        if not (1 <= len(wears) <= 8):
            print(f"  ❌ wear count {len(wears)}")
            errors += 1
        for p in wears:
            issues = check_wear(p)
            if issues:
                print(f"  ❌ {p.name}: {', '.join(issues)}")
                errors += 1
            else:
                print(f"  ✓ {p.name}")
        # Path heuristic: montages directory used as wear source
        if "montages" in str(wear_dir):
            print("  ❌ wear dir is montages/ (forbidden for Wear slot)")
            errors += 1
    else:
        print("  ❌ missing wearOsScreenshots")
        errors += 1

    if phone_dir and phone_dir.is_dir():
        phones = sorted(
            p
            for p in phone_dir.iterdir()
            if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
        )
        print(f"Phone count: {len(phones)} (need 2–8)")
        if not (2 <= len(phones) <= 8):
            print(f"  ❌ phone count {len(phones)}")
            errors += 1
        for p in phones:
            issues = check_phone(p)
            if issues:
                print(f"  ❌ {p.name}: {', '.join(issues)}")
                errors += 1
            else:
                print(f"  ✓ {p.name}")
        if phones and not promo_phone_ok(phones):
            print("  ❌ need ≥4 phone screenshots with a side ≥1080 (promo)")
            errors += 1
        elif phones:
            print("  ✓ promo rule (≥4 × ≥1080)")
    else:
        print("  ⚠️  no phoneScreenshots (optional warning)")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--listing-version",
        help="Audit doc/playstore/listings/<version>/{BCP-47}/images/*",
    )
    parser.add_argument(
        "--lang",
        default="en",
        help="App lang under source trees (default: en); ignored with --listing-version",
    )
    args = parser.parse_args()

    print(f"Guide: {GUIDE.relative_to(REPO)}")
    if not GUIDE.is_file():
        print("❌ missing screenshot-guidelines.md")
        return 1

    errors = 0
    if args.listing_version:
        root = REPO / "doc" / "playstore" / "listings" / args.listing_version
        if not root.is_dir():
            print(f"❌ missing listings/{args.listing_version}")
            return 1
        # Prefer known Play locales; fall back to any dir that has images/
        try:
            from locales import LANG_TO_PLAY_LOCALE

            locales = list(LANG_TO_PLAY_LOCALE.values())
        except ImportError:
            locales = sorted(
                d.name
                for d in root.iterdir()
                if d.is_dir() and (d / "images").is_dir()
            )
        found = False
        for play_locale in locales:
            locale_dir = root / play_locale
            wear = locale_dir / "images" / "wearOsScreenshots"
            phone = locale_dir / "images" / "phoneScreenshots"
            if not wear.is_dir() and not phone.is_dir():
                continue
            found = True
            errors += audit_dir(wear, phone if phone.is_dir() else None, play_locale)
        if not found:
            print(
                f"❌ no {{BCP-47}}/images under listings/{args.listing_version}"
            )
            return 1
    else:
        # Source trees
        wear_screen = REPO / "screenshots" / "wear" / "screen" / args.lang
        phone_montages = REPO / "screenshots" / "phone" / "montages" / args.lang
        print("\n## Source policy check")
        if wear_screen.is_dir():
            errors += audit_dir(wear_screen, phone_montages if phone_montages.is_dir() else None, f"sources lang={args.lang}")
        else:
            print(f"  ❌ missing {wear_screen.relative_to(REPO)}")
            errors += 1

    print("\n## Verdict")
    if errors:
        print(f"FAIL — {errors} issue(s)")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
