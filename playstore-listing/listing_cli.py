#!/usr/bin/env python3
"""Play Store listing CLI — generate, translate (DeepL), validate, upload.

Usage:
  python3 scripts/playstore/listing_cli.py generate [--version 14.0.0]
  python3 scripts/playstore/listing_cli.py translate [--languages de es …] [--overwrite]
  python3 scripts/playstore/listing_cli.py validate [--version 14.0.0]
  python3 scripts/playstore/listing_cli.py upload --draft|--dry-run|--commit [--version 14.0.0]

Translations reuse ``i18n/translate.py`` (DeepL + ``i18n/glossary/{lang}.md``).
Source of truth for English: ``scripts/playstore/listing_copy.py``.
Per-lang editorial files: ``doc/playstore/text-{lang}.md`` (manifest template).

Auth for upload:
  GOOGLE_APPLICATION_CREDENTIALS or scripts/.play-service-account.json
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Optional

_PLAYSTORE_DIR = Path(__file__).resolve().parent
# When vendored in geoking-tools/playstore-listing, DeepL helpers live in ../translate.
# When copied under an app's scripts/playstore, helpers live in <repo>/i18n.
_TOOLS_TRANSLATE = _PLAYSTORE_DIR.parent / "translate"
_APP_I18N = _PLAYSTORE_DIR.parent.parent / "i18n"
if (_TOOLS_TRANSLATE / "translate.py").is_file():
    REPO_ROOT = Path.cwd()  # app root when invoked from an app
    _I18N_DIR = _TOOLS_TRANSLATE
else:
    REPO_ROOT = _PLAYSTORE_DIR.parent.parent
    _I18N_DIR = _APP_I18N
if str(_PLAYSTORE_DIR) not in sys.path:
    sys.path.insert(0, str(_PLAYSTORE_DIR))
if str(_I18N_DIR) not in sys.path:
    sys.path.insert(0, str(_I18N_DIR))
# Prefer app-local listing copy (Arthur, Vincent, …) over the Scora default shipped here.
_APP_LISTING = REPO_ROOT / "scripts" / "playstore"
if (_APP_LISTING / "listing_copy.py").is_file():
    sys.path.insert(0, str(_APP_LISTING))

from listing_copy import (  # noqa: E402
    APP_TITLE,
    SOURCE_COPY,
    SOURCE_LANG,
    ListingCopy,
)
from locales import (  # noqa: E402
    FORBIDDEN_BREAK_TRANSLATIONS,
    FULL_MAX,
    LANG_TO_PLAY_LOCALE,
    PHONE_SCREENSHOTS,
    SHORT_MAX,
    TITLE_MAX,
    WEAR_SCREENSHOTS,
)
from translate import (  # noqa: E402
    build_deepl_context,
    deepl_translate_bulk,
    get_deepl_endpoint,
    resolve_deepl_api_key,
)
from languages import deepl_code  # noqa: E402
MANIFEST_PATH = REPO_ROOT / "scripts" / "project.manifest.json"
SCREENSHOT_SOURCES = REPO_ROOT / "website" / "screenshot-sources.json"
LISTINGS_DIR = REPO_ROOT / "doc" / "playstore" / "listings"
DEFAULT_SA = REPO_ROOT / "scripts" / ".play-service-account.json"
ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"

DEFAULT_PATH_TEMPLATES = {
    "changelog": "doc/playstore/changelog-{lang}.md",
    "listingText": "doc/playstore/text-{lang}.md",
}


def load_project_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.is_file():
        return {}
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def playstore_config() -> dict[str, Any]:
    return load_project_manifest().get("build", {}).get("playStore", {})


def path_template(key: str) -> str:
    return str(playstore_config().get(key) or DEFAULT_PATH_TEMPLATES[key])


def path_for(key: str, lang: str) -> Path:
    return REPO_ROOT / path_template(key).format(lang=lang)


def package_name() -> str:
    m = load_project_manifest()
    return (
        m.get("project", {}).get("playStorePackage")
        or m.get("project", {}).get("package")
        or "fr.geoking.tennis.scoreboard.wear"
    )


def read_listing_version() -> str:
    """Version folder name for listings/ — Scora extraprop, else playstore/version.properties."""
    build = REPO_ROOT / "build.gradle.kts"
    if build.is_file():
        text = build.read_text(encoding="utf-8")
        match = re.search(r'set\("scoraVersionName",\s*"([^"]+)"\)', text)
        if match:
            return match.group(1)
    props = REPO_ROOT / "playstore" / "version.properties"
    if props.is_file():
        for line in props.read_text(encoding="utf-8").splitlines():
            if line.startswith("versionName="):
                return line.split("=", 1)[1].strip().removeprefix("v")
    raise SystemExit(
        "Could not resolve listing version (scoraVersionName or playstore/version.properties)"
    )


def require_wear_screenshots() -> bool:
    return bool(playstore_config().get("requireWearScreenshots", True))


# Back-compat alias
def read_scora_version() -> str:
    return read_listing_version()


def load_screenshot_sources() -> dict[str, Any]:
    if not SCREENSHOT_SOURCES.is_file():
        return {}
    return json.loads(SCREENSHOT_SOURCES.read_text(encoding="utf-8"))


def wear_framed_dir() -> Path:
    sources = load_screenshot_sources()
    rel = sources.get("wearFramedDir", "screenshots/wear/framed")
    return REPO_ROOT / rel


def wear_screen_dir() -> Path:
    sources = load_screenshot_sources()
    rel = sources.get("wearScreenDir", "screenshots/wear/screen")
    return REPO_ROOT / rel


def phone_montages_dir() -> Path:
    sources = load_screenshot_sources()
    rel = sources.get("phoneMontagesDir", "screenshots/phone/montages")
    return REPO_ROOT / rel


def phone_dirs(lang: Optional[str] = None) -> list[Path]:
    """Prefer website companion (may include high-res JPGs), then Roborazzi phone dir.

    When ``lang`` is set, prefer ``{dir}/{lang}/`` then flat / ``en/``.
    """
    sources = load_screenshot_sources()
    dirs: list[Path] = []
    companion = sources.get("websiteCompanionDir", "website/assets/public/images/companion")
    phone = sources.get("phoneDir", "screenshots/phone")
    for rel in (companion, phone):
        path = REPO_ROOT / rel
        if lang:
            for candidate in (path / lang, path / "en", path):
                if candidate.is_dir():
                    dirs.append(candidate)
        elif path.is_dir():
            dirs.append(path)
    # Dedupe while preserving order
    seen: set[Path] = set()
    unique: list[Path] = []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            unique.append(d)
    return unique


def resolve_wear_screen(name: str, lang: str) -> Optional[Path]:
    """Prefer ``screen/{lang}/name``, then ``screen/en/name``."""
    root = wear_screen_dir()
    for path in (root / lang / name, root / "en" / name, root / name):
        if path.is_file():
            return path
    return None


def resolve_wear_framed(name: str, lang: str) -> Optional[Path]:
    """Prefer ``framed/{lang}/name``, then flat, then ``framed/en/name``."""
    root = wear_framed_dir()
    for path in (root / lang / name, root / name, root / "en" / name):
        if path.is_file():
            return path
    return None


def resolve_wear_listing_images(lang: str) -> list[tuple[str, Path]]:
    """Ordered (dest_filename, src) for Wear Play screenshots.

    WO-G5: UI-only, no marketing montages. Prefer ``screenshots/wear/screen``,
    then framed (≥384).
    """
    out: list[tuple[str, Path]] = []
    for i, name in enumerate(WEAR_SCREENSHOTS, start=1):
        src = resolve_wear_screen(name, lang) or resolve_wear_framed(name, lang)
        if src is not None:
            # Skip framed dumps that are below Play minimum (common after normalize)
            try:
                from PIL import Image

                with Image.open(src) as im:
                    if min(im.size) < 384:
                        src = resolve_wear_screen(name, lang)
                        if src is None:
                            continue
            except Exception:
                pass
            out.append((f"{i:02d}_{name}", src))
    return out


def resolve_phone_listing_images(lang: str) -> list[tuple[str, Path]]:
    """Ordered (dest_filename, src) for phone Play screenshots.

    Prefer composed montages when present, else ``PHONE_SCREENSHOTS`` sources.
    """
    montages = phone_montages_dir()
    for candidate in (montages / lang, montages / "en"):
        if not candidate.is_dir():
            continue
        files = sorted(p for p in candidate.glob("*.png") if p.is_file())
        if files:
            return [(p.name, p) for p in files]

    out: list[tuple[str, Path]] = []
    for i, name in enumerate(PHONE_SCREENSHOTS, start=1):
        src = find_phone_file(name, lang)
        if src is not None:
            out.append((f"{i:02d}_{src.name}", src))
    return out


def find_phone_file(name: str, lang: Optional[str] = None) -> Optional[Path]:
    for directory in phone_dirs(lang):
        candidate = directory / name
        if candidate.is_file():
            return candidate
    stem = Path(name).stem
    for directory in phone_dirs(lang):
        for alt in (
            f"{stem}.png",
            f"{stem}.jpg",
            f"companion_{stem}.png",
            name.replace("phone-", "companion_").replace(".jpg", ".png"),
        ):
            candidate = directory / alt
            if candidate.is_file():
                return candidate
    if lang and lang != "en":
        return find_phone_file(name, "en")
    return None


def prepare_locale_image_dirs(locale_dir: Path) -> tuple[Path, Path]:
    """Fastlane / Play Console layout under the BCP-47 locale folder::

        {locale}/images/wearOsScreenshots/   # real PNGs (WO-G5)
        {locale}/images/phoneScreenshots/    # real PNGs

    Clears legacy symlinks (including old ``_images/{lang}`` indirection).
    """
    images_dir = locale_dir / "images"
    if images_dir.is_symlink():
        images_dir.unlink()
    images_dir.mkdir(parents=True, exist_ok=True)

    wear = images_dir / "wearOsScreenshots"
    phone = images_dir / "phoneScreenshots"
    for slot in (wear, phone):
        if slot.is_symlink():
            slot.unlink()
        elif slot.is_dir():
            shutil.rmtree(slot)
        elif slot.exists():
            slot.unlink()
        slot.mkdir(parents=True, exist_ok=True)
    return wear, phone


def listing_version_dir(version: str) -> Path:
    listings = playstore_config().get("listingsDir", "doc/playstore/listings")
    return REPO_ROOT / listings / version


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.strip() + "\n", encoding="utf-8")


def copy_image(src: Path, dest: Path, *, flatten_rgb: bool = False) -> bool:
    """Copy image; optionally flatten alpha to opaque black (Wear Play rule)."""
    if not src.is_file():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    if flatten_rgb:
        try:
            from PIL import Image

            with Image.open(src) as im:
                if im.mode in ("RGBA", "LA") or (
                    im.mode == "P" and "transparency" in im.info
                ):
                    rgba = im.convert("RGBA")
                    bg = Image.new("RGB", rgba.size, (0, 0, 0))
                    bg.paste(rgba, mask=rgba.split()[-1])
                    bg.save(dest, format="PNG", optimize=True)
                    return True
                im.convert("RGB").save(dest, format="PNG", optimize=True)
                return True
        except Exception:
            pass
    shutil.copy2(src, dest)
    return True


def format_listing_markdown(lang: str, copy: ListingCopy) -> str:
    header = lang.upper()
    return (
        f"# Play store translations\n\n"
        f"# {header}\n\n"
        f"## name\n\n"
        f"{copy['title']}\n\n"
        f"## short description\n\n"
        f"{copy['short_description']}\n\n"
        f"## full description\n\n"
        f"{copy['full_description'].strip()}\n"
    )


def parse_listing_markdown(content: str) -> ListingCopy:
    """Parse ``text-{lang}.md`` sections (name / short / full)."""
    text = content.replace("\r\n", "\n")
    sections: dict[str, str] = {}
    current: Optional[str] = None
    buf: list[str] = []

    def flush() -> None:
        nonlocal current, buf
        if current is not None:
            sections[current] = "\n".join(buf).strip()
        buf = []

    for line in text.split("\n"):
        heading = re.match(r"^##\s+(name|short description|full description)\s*$", line, re.I)
        if heading:
            flush()
            key = heading.group(1).lower()
            if key == "name":
                current = "title"
            elif key.startswith("short"):
                current = "short_description"
            else:
                current = "full_description"
            continue
        if current is not None:
            buf.append(line)
    flush()

    title = sections.get("title", APP_TITLE).strip() or APP_TITLE
    short = sections.get("short_description", "").strip()
    full = sections.get("full_description", "").strip()
    if not short or not full:
        raise ValueError("Missing short description or full description section")
    return {
        "title": title,
        "short_description": short,
        "full_description": full,
    }


def write_listing_markdown(lang: str, copy: ListingCopy) -> Path:
    path = path_for("listingText", lang)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(format_listing_markdown(lang, copy), encoding="utf-8")
    return path


def load_listing_copy(lang: str) -> ListingCopy:
    path = path_for("listingText", lang)
    if path.is_file():
        return parse_listing_markdown(path.read_text(encoding="utf-8"))
    if lang == SOURCE_LANG:
        return dict(SOURCE_COPY)  # type: ignore[return-value]
    raise FileNotFoundError(
        f"Missing {path.relative_to(REPO_ROOT)}. Run `translate` or add curated copy."
    )


def sync_source_english_markdown() -> Path:
    """Keep EN markdown aligned with listing_copy.SOURCE_COPY."""
    return write_listing_markdown(SOURCE_LANG, SOURCE_COPY)


def write_locale_listing_files(version: str, lang: str, copy: ListingCopy) -> Path:
    play_locale = LANG_TO_PLAY_LOCALE[lang]
    locale_dir = listing_version_dir(version) / play_locale
    write_text(locale_dir / "title.txt", copy["title"])
    write_text(locale_dir / "short_description.txt", copy["short_description"])
    write_text(locale_dir / "full_description.txt", copy["full_description"])
    return locale_dir


def truncate_short(text: str, max_len: int = SHORT_MAX) -> str:
    text = " ".join(text.split())
    if len(text) <= max_len:
        return text
    cut = text[: max_len - 1].rsplit(" ", 1)[0].rstrip(" ,;:.-")
    if not cut:
        cut = text[: max_len - 1]
    return cut + "…"


def translate_listing_copy(
    target_lang: str,
    api_key: str,
    *,
    source: Optional[ListingCopy] = None,
    sleep_ms: int = 150,
) -> ListingCopy:
    """Translate EN short + full via shared ``i18n/translate.py`` DeepL helpers."""
    import os

    if target_lang == SOURCE_LANG:
        return dict(source or SOURCE_COPY)  # type: ignore[return-value]

    deepl_target = deepl_code(target_lang)
    if not deepl_target:
        raise SystemExit(f"DeepL does not support lang={target_lang}")

    src = source or SOURCE_COPY
    context = build_deepl_context(
        os.environ.get(
            "DEEPL_CONTEXT",
            "tennis, match, scoreboard, Wear OS, Google Play store listing",
        ),
        target_lang,
    )
    endpoint = get_deepl_endpoint(api_key)
    endpoint_display = "free" if "api-free" in endpoint else "paid"
    print(f"   🌐 DeepL EN → {deepl_target} [{endpoint_display}] (lang={target_lang})")

    translated = deepl_translate_bulk(
        [src["short_description"], src["full_description"]],
        source="EN",
        target=deepl_target,
        api_key=api_key,
        sleep_ms=sleep_ms,
        context=context,
    )
    if len(translated) != 2:
        raise SystemExit(f"DeepL returned unexpected payload for {target_lang}")

    short = truncate_short(translated[0].strip())
    full = translated[1].strip()
    if "scorawatch.com" not in full and "scorawatch.com" in src["full_description"]:
        full = full.rstrip() + "\n\nhttps://scorawatch.com"
    full = re.sub(r"\bScora\b", APP_TITLE, full)
    return {
        "title": APP_TITLE,
        "short_description": short,
        "full_description": full,
    }


def cmd_translate(args: argparse.Namespace) -> int:
    """Translate EN listing copy to all (or selected) app languages via DeepL."""
    sync_source_english_markdown()
    api_key = resolve_deepl_api_key(args.deepl_api_key)
    version = args.version or read_scora_version()
    out = listing_version_dir(version)
    out.mkdir(parents=True, exist_ok=True)

    if args.languages:
        targets = [l for l in args.languages if l != SOURCE_LANG]
    else:
        targets = [l for l in LANG_TO_PLAY_LOCALE if l != SOURCE_LANG]

    unknown = [l for l in targets if l not in LANG_TO_PLAY_LOCALE]
    if unknown:
        raise SystemExit(f"Unknown languages: {', '.join(unknown)}")

    unsupported = [l for l in targets if not deepl_code(l)]
    if unsupported:
        raise SystemExit(f"No DeepL mapping for: {', '.join(unsupported)}")

    source = load_listing_copy(SOURCE_LANG)
    translated = 0
    skipped = 0

    for lang in targets:
        md_path = path_for("listingText", lang)
        if md_path.is_file() and not args.overwrite:
            print(f"⏭️  {lang}: keep existing {md_path.relative_to(REPO_ROOT)} (use --overwrite)")
            skipped += 1
            try:
                write_locale_listing_files(version, lang, load_listing_copy(lang))
            except ValueError as e:
                print(f"⚠️  {lang}: {e}")
            continue

        print(f"🔤 Translating listing → {lang}")
        copy = translate_listing_copy(
            lang,
            api_key,
            source=source,
            sleep_ms=args.sleep_ms,
        )
        write_listing_markdown(lang, copy)
        write_locale_listing_files(version, lang, copy)
        print(f"   ✅ {path_for('listingText', lang).relative_to(REPO_ROOT)}")
        translated += 1

    write_locale_listing_files(version, SOURCE_LANG, source)

    print(f"✅ Translate done — {translated} new/updated, {skipped} kept.")
    print("   Tip: run `generate` to refresh screenshots + manifest.json")
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    version = args.version or read_scora_version()
    out = listing_version_dir(version)
    out.mkdir(parents=True, exist_ok=True)

    sync_source_english_markdown()

    wear_src = wear_framed_dir()
    missing_wear: list[str] = []
    missing_phone: list[str] = []
    missing_copy: list[str] = []

    langs = getattr(args, "languages", None) or None
    if langs:
        unknown = [l for l in langs if l not in LANG_TO_PLAY_LOCALE]
        if unknown:
            raise SystemExit(f"Unknown language(s): {', '.join(unknown)}")
        target_langs = list(langs)
    else:
        target_langs = list(LANG_TO_PLAY_LOCALE)

    # Drop legacy shared pack (_images/{app-lang}/ + symlinks).
    legacy_images = out / "_images"
    if legacy_images.exists():
        shutil.rmtree(legacy_images)

    locale_manifest: list[dict[str, Any]] = []
    wear_copied_by_lang: dict[str, int] = {}
    phone_copied_by_lang: dict[str, int] = {}

    for lang in target_langs:
        play_locale = LANG_TO_PLAY_LOCALE[lang]
        try:
            copy = load_listing_copy(lang)
        except FileNotFoundError:
            missing_copy.append(lang)
            continue

        locale_dir = write_locale_listing_files(version, lang, copy)
        lang_wear, lang_phone = prepare_locale_image_dirs(locale_dir)

        wear_copied = 0
        wear_images = resolve_wear_listing_images(lang)
        if not wear_images and lang == SOURCE_LANG:
            missing_wear.extend(WEAR_SCREENSHOTS)
        for dest_name, src in wear_images:
            if copy_image(src, lang_wear / dest_name, flatten_rgb=True):
                wear_copied += 1

        phone_copied = 0
        phone_images = resolve_phone_listing_images(lang)
        if not phone_images and lang == SOURCE_LANG:
            missing_phone.extend(PHONE_SCREENSHOTS)
        for dest_name, src in phone_images:
            if copy_image(src, lang_phone / dest_name):
                phone_copied += 1

        wear_copied_by_lang[lang] = wear_copied
        phone_copied_by_lang[lang] = phone_copied

        if lang == SOURCE_LANG:
            write_listing_markdown(lang, copy)

        locale_manifest.append(
            {
                "lang": lang,
                "locale": play_locale,
                "wearScreenshots": wear_copied,
                "phoneScreenshots": phone_copied,
                "listingText": str(path_for("listingText", lang).relative_to(REPO_ROOT)),
            }
        )

    # Partial generate: keep prior locale entries for langs we did not touch.
    if langs and (out / "manifest.json").is_file():
        try:
            prev = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
            kept = [
                e
                for e in prev.get("locales", [])
                if e.get("lang") not in set(target_langs)
            ]
            locale_manifest = kept + locale_manifest
            locale_manifest.sort(key=lambda e: e.get("lang", ""))
        except Exception:
            pass

    listing_manifest = {
        "version": version,
        "package": package_name(),
        "locales": locale_manifest,
        "wearScreenshots": WEAR_SCREENSHOTS,
        "wearSource": (
            "screen"
            if (wear_screen_dir() / "en").is_dir()
            and any((wear_screen_dir() / "en").glob("*.png"))
            else "framed"
        ),
        "phoneSource": (
            "montages"
            if (phone_montages_dir() / "en").is_dir()
            and any((phone_montages_dir() / "en").glob("*.png"))
            else "raw"
        ),
        "wearScreenDir": str(wear_screen_dir().relative_to(REPO_ROOT)),
        "phoneMontagesDir": str(phone_montages_dir().relative_to(REPO_ROOT)),
        "phoneScreenshots": PHONE_SCREENSHOTS,
        "wearFramedDir": str(wear_src.relative_to(REPO_ROOT)),
        "phoneDirs": [str(p.relative_to(REPO_ROOT)) for p in phone_dirs()],
        "imagesLayout": "{BCP-47}/images/wearOsScreenshots|phoneScreenshots",
        "missingWear": missing_wear,
        "missingPhone": missing_phone,
        "missingCopy": missing_copy,
        "pathTemplates": {
            "changelog": path_template("changelog"),
            "listingText": path_template("listingText"),
        },
    }
    (out / "manifest.json").write_text(
        json.dumps(listing_manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"✅ Generated listing at {out.relative_to(REPO_ROOT)}")
    print(f"   Locales with copy: {len(locale_manifest)}")
    print(
        "   Images: "
        + ", ".join(
            f"{lang}=w{wear_copied_by_lang.get(lang, 0)}/p{phone_copied_by_lang.get(lang, 0)}"
            for lang in wear_copied_by_lang
        )
    )
    if missing_copy:
        print(
            f"⚠️  Missing listing text for: {', '.join(missing_copy)}\n"
            f"   Run: listing_cli.py translate"
        )
    if missing_wear:
        print(f"⚠️  Missing wear framed (EN): {', '.join(missing_wear)}")
    if missing_phone:
        print(f"⚠️  Missing phone (EN): {', '.join(missing_phone)}")
    return 0 if not missing_wear and not missing_copy else 1


def read_locale_files(locale_dir: Path) -> dict[str, str]:
    return {
        "title": (locale_dir / "title.txt").read_text(encoding="utf-8").strip(),
        "short_description": (locale_dir / "short_description.txt")
        .read_text(encoding="utf-8")
        .strip(),
        "full_description": (locale_dir / "full_description.txt")
        .read_text(encoding="utf-8")
        .strip(),
    }


def cmd_validate(args: argparse.Namespace) -> int:
    version = args.version or read_scora_version()
    out = listing_version_dir(version)
    if not out.is_dir():
        print(f"❌ Listing dir missing: {out}. Run `generate` first.")
        return 1

    errors: list[str] = []
    warnings: list[str] = []

    for lang, play_locale in LANG_TO_PLAY_LOCALE.items():
        locale_dir = out / play_locale
        if not locale_dir.is_dir():
            if play_locale == "en-US":
                errors.append(f"Missing required locale dir: {play_locale}")
            continue
        try:
            texts = read_locale_files(locale_dir)
        except FileNotFoundError as e:
            errors.append(f"{play_locale}: {e}")
            continue

        if len(texts["title"]) > TITLE_MAX:
            errors.append(
                f"{play_locale} title {len(texts['title'])}>{TITLE_MAX}: {texts['title']!r}"
            )
        if len(texts["short_description"]) > SHORT_MAX:
            errors.append(
                f"{play_locale} short {len(texts['short_description'])}>{SHORT_MAX}"
            )
        if len(texts["full_description"]) > FULL_MAX:
            errors.append(
                f"{play_locale} full {len(texts['full_description'])}>{FULL_MAX}"
            )
        if not texts["title"] or not texts["short_description"] or not texts["full_description"]:
            errors.append(f"{play_locale}: empty title/short/full")

        lower_full = texts["full_description"].lower()
        for bad in FORBIDDEN_BREAK_TRANSLATIONS:
            if bad in ("pause", "pausa"):
                continue
            if bad in lower_full:
                warnings.append(f"{play_locale}: suspicious term {bad!r} in full description")

        for slot in ("wearOsScreenshots", "phoneScreenshots"):
            dest = locale_dir / "images" / slot
            if dest.is_symlink():
                errors.append(
                    f"{play_locale}: images/{slot} must be a real directory "
                    f"(Fastlane BCP-47 layout), not a symlink"
                )
                continue
            if not dest.is_dir():
                errors.append(f"{play_locale}: missing images/{slot}")

        wear_imgs = sorted((locale_dir / "images" / "wearOsScreenshots").glob("*"))
        phone_imgs = sorted((locale_dir / "images" / "phoneScreenshots").glob("*"))
        if not wear_imgs:
            if require_wear_screenshots():
                errors.append(f"{play_locale}: no wearOsScreenshots")
            else:
                warnings.append(f"{play_locale}: no wearOsScreenshots (optional for this app)")
        elif len(wear_imgs) < 4:
            warnings.append(f"{play_locale}: only {len(wear_imgs)} wear screenshots")
        if not phone_imgs:
            errors.append(f"{play_locale}: no phoneScreenshots")

        md_path = path_for("listingText", lang)
        if not md_path.is_file():
            warnings.append(f"{lang}: missing editorial {md_path.relative_to(REPO_ROOT)}")

    if (out / "_images").exists():
        errors.append(
            "legacy _images/ present — re-run generate (images live under "
            "{BCP-47}/images/)"
        )

    if warnings:
        for w in warnings:
            print(f"⚠️  {w}")
    if errors:
        for e in errors:
            print(f"❌ {e}")
        print(f"\nValidation failed ({len(errors)} error(s)).")
        return 1

    # Dimensional / WO-G5 checks on packed images
    try:
        from validate_screenshots import audit_dir as _audit_shot_dir
    except ImportError:
        _audit_shot_dir = None  # type: ignore[assignment]
    if _audit_shot_dir is not None:
        shot_errors = 0
        wear_required = require_wear_screenshots()
        for _lang, play_locale in LANG_TO_PLAY_LOCALE.items():
            locale_dir = out / play_locale
            if not locale_dir.is_dir():
                continue
            shot_errors += _audit_shot_dir(
                locale_dir / "images" / "wearOsScreenshots",
                locale_dir / "images" / "phoneScreenshots",
                play_locale,
                require_wear=wear_required,
            )
        if shot_errors:
            print(f"\nValidation failed ({shot_errors} screenshot guideline issue(s)).")
            print("See doc/playstore/screenshot-guidelines.md")
            return 1

    print(f"✅ Listing {version} OK ({len(LANG_TO_PLAY_LOCALE)} locales).")
    return 0


def resolve_credentials_path() -> Path:
    import os

    env = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if env:
        path = Path(env)
        if path.is_file():
            return path
    if DEFAULT_SA.is_file():
        return DEFAULT_SA
    raise SystemExit(
        "No Play service account credentials found.\n"
        "Set GOOGLE_APPLICATION_CREDENTIALS or place scripts/.play-service-account.json\n"
        "(see ./scripts/dashboard/setup.sh or ./scripts/setup-release.sh play)."
    )


def play_urls() -> dict[str, str]:
    """Play Console / store URLs from ``scripts/project.manifest.json``."""
    play = load_project_manifest().get("urls", {}).get("play", {}) or {}
    store = load_project_manifest().get("urls", {}).get("store", {}) or {}
    return {
        "storeListing": str(play.get("storeListing") or ""),
        "publishingOverview": str(play.get("publishingOverview") or ""),
        "releases": str(play.get("releases") or ""),
        "dashboard": str(play.get("dashboard") or ""),
        "apiAccess": str(play.get("apiAccess") or ""),
        "usersAndPermissions": str(play.get("usersAndPermissions") or ""),
        "publicListing": str(store.get("listing") or ""),
    }


def print_play_console_links(*, context: str = "upload") -> None:
    """Print clickable Play Console links for the operator to follow along."""
    urls = play_urls()
    print("🔗 Play Console:")
    if context in {"upload", "all"}:
        if urls["storeListing"]:
            print(f"   Store listing:        {urls['storeListing']}")
        if urls["publishingOverview"]:
            print(f"   Publishing overview:  {urls['publishingOverview']}")
        if urls["releases"]:
            print(f"   Releases:             {urls['releases']}")
        if urls["publicListing"]:
            print(f"   Public store page:    {urls['publicListing']}")
    if context in {"permissions", "all"}:
        if urls["apiAccess"]:
            print(f"   API access:           {urls['apiAccess']}")
        if urls["usersAndPermissions"]:
            print(f"   Users & permissions:  {urls['usersAndPermissions']}")


def service_account_email() -> str:
    path = resolve_credentials_path()
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("client_email") or path.name
    except Exception:
        return str(path)


def permission_denied_hint() -> str:
    urls = play_urls()
    api_access = urls["apiAccess"] or "https://play.google.com/console → Setup → API access"
    users = urls["usersAndPermissions"]
    sa = service_account_email()
    lines = [
        f"\nPermission denied for {sa}.",
        "Listing upload needs Play Console app permission "
        "CAN_MANAGE_PUBLIC_LISTING (UI: \"Manage store presence\").",
        "The growth SA usually only has view permissions for metrics.",
        "",
        "Fix (Play Console admin Google account):",
        "  ./scripts/dashboard/play_permissions.sh --for-listing --yes",
        f"  API access: {api_access}",
    ]
    if users:
        lines.append(f"  Users & permissions: {users}")
    lines.append(
        "Alternatively point GOOGLE_APPLICATION_CREDENTIALS at the deploy SA "
        "(CI secret SERVICE_ACCOUNT_JSON) that already publishes AABs."
    )
    return "\n".join(lines) + "\n"


def build_publisher_service():
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError as e:
        raise SystemExit(
            "Missing Google API deps. Install with:\n"
            "  pip install -r scripts/playstore/requirements.txt\n"
            f"({e})"
        ) from e

    creds_path = resolve_credentials_path()
    creds = service_account.Credentials.from_service_account_file(
        str(creds_path),
        scopes=[ANDROID_PUBLISHER_SCOPE],
    )
    print(f"🔑 Service account: {service_account_email()}")
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def upload_images(
    service,
    package: str,
    edit_id: str,
    language: str,
    image_type: str,
    directory: Path,
) -> int:
    """Replace all images of a type for a language. Returns uploaded count."""
    from googleapiclient.http import MediaFileUpload

    service.edits().images().deleteall(
        packageName=package,
        editId=edit_id,
        language=language,
        imageType=image_type,
    ).execute()

    count = 0
    for path in sorted(directory.glob("*")):
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
            continue
        media = MediaFileUpload(str(path), mimetype=_mime_for(path), resumable=False)
        service.edits().images().upload(
            packageName=package,
            editId=edit_id,
            language=language,
            imageType=image_type,
            media_body=media,
        ).execute()
        count += 1
    return count


def _mime_for(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if ext == ".webp":
        return "image/webp"
    return "image/png"


def parse_play_locales(raw: Optional[str], *, default_all: bool = False) -> set[str]:
    """Parse comma-separated Play BCP-47 locales, or ``all`` / ``*``."""
    if raw is None or raw.strip() == "":
        return set(LANG_TO_PLAY_LOCALE.values()) if default_all else {"en-US"}
    if raw.strip().lower() in {"all", "*"}:
        return set(LANG_TO_PLAY_LOCALE.values())
    return {part.strip() for part in raw.split(",") if part.strip()}


def parse_image_locales(raw: Optional[str]) -> set[str]:
    return parse_play_locales(raw, default_all=False)


def _http_error_message(exc: BaseException) -> str:
    content = getattr(exc, "content", None)
    if content is not None:
        try:
            raw = content.decode("utf-8") if isinstance(content, (bytes, bytearray)) else str(content)
            if raw:
                return raw
        except Exception:
            pass
    return str(exc)


def commit_edit(
    service,
    package: str,
    edit_id: str,
    *,
    draft: bool,
) -> None:
    """Commit an edit, adapting to Play Console managed-publishing rules.

    Some apps reject ``changesNotSentForReview=true`` ("Changes are sent for
    review automatically"); others require it. ``--draft`` prefers the flag and
    falls back to a plain commit when Play refuses it.
    """
    from googleapiclient.errors import HttpError

    base = {"packageName": package, "editId": edit_id}
    if not draft:
        print("🚀 Committing listing (may send for review)…")
        service.edits().commit(**base).execute()
        return

    print("🚀 Committing as draft (changesNotSentForReview=true)…")
    try:
        service.edits().commit(**base, changesNotSentForReview=True).execute()
        return
    except HttpError as e:
        msg = _http_error_message(e)
        if e.resp.status != 400 or "changesNotSentForReview" not in msg:
            raise
        if "must not be set" not in msg and "must be set" not in msg:
            raise
        print(
            "⚠️  Play Console auto-sends changes for review — "
            "retrying commit without changesNotSentForReview."
        )
        service.edits().commit(**base).execute()


def snapshot_listing_tree(src: Path) -> Path:
    """Copy listing tree to a temp dir so upload is race-safe vs concurrent generate."""
    dest = Path(tempfile.mkdtemp(prefix="scora-listing-upload-"))
    shutil.copytree(src, dest / "listing", symlinks=False, dirs_exist_ok=False)
    return dest / "listing"


def cmd_upload(args: argparse.Namespace) -> int:
    modes = [args.draft, args.dry_run, args.commit]
    if sum(1 for m in modes if m) != 1:
        raise SystemExit("Choose exactly one of --draft, --dry-run, or --commit")

    version = args.version or read_scora_version()
    out = listing_version_dir(version)
    if cmd_validate(argparse.Namespace(version=version)) != 0:
        return 1

    listing_locales = parse_play_locales(
        getattr(args, "locales", None) or "all", default_all=True
    )
    image_locales = parse_image_locales(args.image_locales)
    # When uploading a subset of locales, default images to the same subset
    # unless --image-locales was explicitly set to something else… keep both.
    package = package_name()
    service = build_publisher_service()

    print(f"📦 Package: {package}")
    print(f"📂 Listing: {out.relative_to(REPO_ROOT)}")
    print(f"📝 Listing locales: {', '.join(sorted(listing_locales))}")
    print(f"🖼  Image locales: {', '.join(sorted(image_locales))}")
    print_play_console_links(context="upload")
    if args.dry_run:
        print("🧪 Dry-run: will abandon the edit after upload (no commit).")

    # Materialize texts + images once; ignore concurrent generate/rmtree on out/
    snap_root: Optional[Path] = None
    edit_id: Optional[str] = None
    try:
        snap_root = snapshot_listing_tree(out)
        print(f"📸 Upload snapshot: {snap_root}")

        edit = service.edits().insert(packageName=package, body={}).execute()
        edit_id = edit["id"]
        print(f"✏️  Edit created: {edit_id}")

        for _lang, play_locale in LANG_TO_PLAY_LOCALE.items():
            if play_locale not in listing_locales:
                continue
            locale_dir = snap_root / play_locale
            texts = read_locale_files(locale_dir)
            service.edits().listings().update(
                packageName=package,
                editId=edit_id,
                language=play_locale,
                body={
                    "language": play_locale,
                    "title": texts["title"],
                    "shortDescription": texts["short_description"],
                    "fullDescription": texts["full_description"],
                },
            ).execute()
            print(f"   ✓ listing {play_locale}")

            if play_locale not in image_locales:
                continue

            wear_dir = locale_dir / "images" / "wearOsScreenshots"
            phone_dir = locale_dir / "images" / "phoneScreenshots"
            if wear_dir.is_dir() and any(wear_dir.glob("*")):
                n = upload_images(
                    service, package, edit_id, play_locale, "wearScreenshots", wear_dir
                )
                print(f"   ✓ wearScreenshots ×{n} ({play_locale})")
            if phone_dir.is_dir() and any(phone_dir.glob("*")):
                n = upload_images(
                    service, package, edit_id, play_locale, "phoneScreenshots", phone_dir
                )
                print(f"   ✓ phoneScreenshots ×{n} ({play_locale})")

        if args.dry_run:
            service.edits().delete(packageName=package, editId=edit_id).execute()
            print("✅ Dry-run OK — edit abandoned (nothing published).")
            return 0

        commit_edit(service, package, edit_id, draft=bool(args.draft))
        if args.draft:
            print(
                "✅ Listing committed.\n"
                "   If managed publishing is on, changes may already be in review;\n"
                "   otherwise check Play Console → Publishing overview."
            )
        else:
            print("✅ Listing committed.")
        print_play_console_links(context="upload")
        return 0
    except Exception as e:
        if edit_id is not None:
            try:
                service.edits().delete(packageName=package, editId=edit_id).execute()
                print("↩️  Edit abandoned after error.")
            except Exception:
                pass
        msg = _http_error_message(e)
        print(f"❌ Upload failed: {msg}")
        if "PERMISSION_DENIED" in msg or '"code": 403' in msg or "403" in msg[:80]:
            print(permission_denied_hint())
            print_play_console_links(context="permissions")
        else:
            print_play_console_links(context="upload")
        raise SystemExit(1) from e
    finally:
        if snap_root is not None:
            shutil.rmtree(snap_root.parent, ignore_errors=True)


def cmd_links(_args: argparse.Namespace) -> int:
    """Print Play Console links from the project manifest."""
    print(f"📦 Package: {package_name()}")
    print_play_console_links(context="all")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate / translate / validate / upload versioned Play Store listings"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="Build doc/playstore/listings/<version>/")
    gen.add_argument("--version", help="Version folder name (default: scoraVersionName)")
    gen.add_argument(
        "--languages",
        "-l",
        nargs="*",
        help="App langs to pack (default: all). Example: -l en",
    )
    gen.set_defaults(func=cmd_generate)

    tr = sub.add_parser(
        "translate",
        help="DeepL-translate EN listing to text-{lang}.md (reuses i18n/translate.py)",
    )
    tr.add_argument("--version", help="Also refresh listing tree for this version")
    tr.add_argument(
        "--languages",
        "-l",
        nargs="*",
        help="Target app langs (default: all except en)",
    )
    tr.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing doc/playstore/text-{lang}.md",
    )
    tr.add_argument("--deepl-api-key", default=None, help="Override DEEPL_API_KEY")
    tr.add_argument("--sleep-ms", type=int, default=150)
    tr.set_defaults(func=cmd_translate)

    val = sub.add_parser("validate", help="Check limits, locales, and images")
    val.add_argument("--version", help="Version folder name (default: scoraVersionName)")
    val.set_defaults(func=cmd_validate)

    links = sub.add_parser("links", help="Print Play Console URLs from project.manifest.json")
    links.set_defaults(func=cmd_links)

    up = sub.add_parser("upload", help="Upload listing via Android Publisher edits API")
    up.add_argument("--version", help="Version folder name (default: scoraVersionName)")
    up.add_argument(
        "--locales",
        default="all",
        help="Comma-separated Play BCP-47 locales for listing text upload, or 'all' "
        "(default: all).",
    )
    up.add_argument(
        "--image-locales",
        default="en-US",
        help="Comma-separated Play locales for screenshot upload, or 'all' "
        "(default: en-US). Each locale uploads from "
        "{BCP-47}/images/wearOsScreenshots|phoneScreenshots.",
    )
    mode = up.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--draft",
        action="store_true",
        help="Commit listing; tries changesNotSentForReview=true, falls back if Play "
        "auto-sends for review",
    )
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Create edit and upload into it, then abandon (nothing published)",
    )
    mode.add_argument(
        "--commit",
        action="store_true",
        help="Commit listing changes (may auto-send for review)",
    )
    up.set_defaults(func=cmd_upload)

    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
