#!/usr/bin/env python3
"""Copy app Roborazzi/Play screenshots into website/ from screenshot-sources.json.

Config lives in the app repo at website/screenshot-sources.json (or --config).
Shared across GeoKing monorepos — Scora-style sync without app-local Python.

Example config:

{
  "locales": ["en", "fr"],
  "copies": [
    {
      "from": "screenshots/phone/framed/{locale}",
      "to": "website/assets/screenshots/{locale}",
      "glob": "*.png"
    }
  ]
}

Legacy Arthur keys phoneDir / phoneMontagesDir are still accepted.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def expand(template: str, locale: str) -> str:
    return (
        template.replace("{locale}", locale)
        .replace("{lang}", locale)
        .replace("{Locale}", locale)
    )


def resolve_locale_dir(base: Path, locale: str) -> Path | None:
    """Prefer base/{locale}, then base, then base/en."""
    for candidate in (base / locale, base, base / "en"):
        if candidate.is_dir():
            return candidate
    return None


def collect_files(directory: Path, pattern: str) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.glob(pattern) if p.is_file())


def load_config(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"Config must be a JSON object: {path}")
    return data


def normalize_copies(cfg: dict) -> list[dict]:
    copies = cfg.get("copies")
    if isinstance(copies, list) and copies:
        return copies

    # Legacy Arthur / early GeoKing shape
    out: list[dict] = []
    phone = cfg.get("phoneDir") or cfg.get("phoneFramedDir")
    if phone:
        out.append(
            {
                "from": f"{phone.rstrip('/')}/{{locale}}",
                "to": "website/assets/screenshots/{locale}",
                "glob": "*.png",
            }
        )
    montages = cfg.get("phoneMontagesDir")
    if montages:
        out.append(
            {
                "from": f"{montages.rstrip('/')}/{{locale}}",
                "to": "website/assets/montages/{locale}",
                "glob": "*.png",
            }
        )
    if not out:
        raise SystemExit(
            "screenshot-sources.json needs a non-empty 'copies' array "
            "(or legacy phoneDir / phoneMontagesDir)."
        )
    return out


def parse_locales(cfg: dict, override: str | None) -> list[str]:
    if override:
        return [p.strip().lower() for p in override.split(",") if p.strip()]
    raw = cfg.get("locales") or ["en", "fr"]
    if isinstance(raw, str):
        return [p.strip().lower() for p in raw.split(",") if p.strip()]
    return [str(x).strip().lower() for x in raw if str(x).strip()]


def run_copy(
    repo_root: Path,
    copies: list[dict],
    locales: list[str],
    *,
    dry_run: bool,
) -> int:
    total = 0
    for locale in locales:
        for entry in copies:
            from_tpl = entry.get("from")
            to_tpl = entry.get("to")
            if not from_tpl or not to_tpl:
                raise SystemExit(f"Each copy needs 'from' and 'to': {entry}")
            pattern = entry.get("glob") or entry.get("pattern") or "*"
            required = entry.get("required") or []

            from_rel = expand(str(from_tpl), locale)
            to_rel = expand(str(to_tpl), locale)
            src_base = (repo_root / from_rel).resolve()
            # If template already included locale dir that doesn't exist, try parent + resolve
            src_dir = src_base if src_base.is_dir() else resolve_locale_dir(
                src_base.parent if src_base.name == locale else src_base, locale
            )
            if src_dir is None:
                if required:
                    raise SystemExit(
                        f"Missing source dir for locale '{locale}': {from_rel} "
                        f"(required: {', '.join(required)})"
                    )
                print(f"· skip {from_rel} (missing)")
                continue

            dst_dir = (repo_root / to_rel).resolve()
            files = collect_files(src_dir, pattern)
            if required:
                names = {p.name for p in files}
                missing = [n for n in required if n not in names]
                if missing:
                    raise SystemExit(
                        f"Missing files in {src_dir} for locale '{locale}': "
                        f"{', '.join(missing)}"
                    )

            if not files:
                print(f"· empty {src_dir.relative_to(repo_root)}")
                continue

            for src in files:
                dst = dst_dir / src.name
                rel_src = src.relative_to(repo_root)
                rel_dst = dst.relative_to(repo_root)
                if dry_run:
                    print(f"  would copy {rel_src} → {rel_dst}")
                else:
                    copy_file(src, dst)
                total += 1
            print(f"✓ {locale}: {len(files)} file(s) → {to_rel}")
    return total


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fill website/ assets from app screenshots (screenshot-sources.json)."
    )
    parser.add_argument(
        "--root",
        default="",
        help="App repo root (default: GK_PROJECT_ROOT or cwd).",
    )
    parser.add_argument(
        "--config",
        default="",
        help="Path to screenshot-sources.json (default: website/screenshot-sources.json).",
    )
    parser.add_argument(
        "--locales",
        default="",
        help="Comma-separated locales override (default: from config).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without copying.",
    )
    args = parser.parse_args()

    import os

    root_raw = args.root or os.environ.get("GK_PROJECT_ROOT") or os.getcwd()
    repo_root = Path(root_raw).resolve()
    config_path = (
        Path(args.config).resolve()
        if args.config
        else repo_root / "website" / "screenshot-sources.json"
    )
    if not config_path.is_file():
        raise SystemExit(f"Config not found: {config_path}")

    cfg = load_config(config_path)
    copies = normalize_copies(cfg)
    locales = parse_locales(cfg, args.locales or None)
    if not locales:
        raise SystemExit("No locales configured")

    print(f"Repo:    {repo_root}")
    print(f"Config:  {config_path.relative_to(repo_root)}")
    print(f"Locales: {', '.join(locales)}")
    total = run_copy(repo_root, copies, locales, dry_run=args.dry_run)
    verb = "Would copy" if args.dry_run else "Copied"
    print(f"✅ {verb} {total} file(s) into website/.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
