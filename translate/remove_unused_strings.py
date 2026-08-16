#!/usr/bin/env python3
"""
Remove unused string and plural resources from Android strings.xml files.

Greps Kotlin and XML under app, shared, wear to find used string/plurals names,
then removes from values/ and values-*/strings.xml those that are defined but
never referenced.

Patterns matched:
  - Kotlin: R.string.xxx, .plurals.xxx (R.plurals, sharedRes.plurals, sharedR.plurals, wearR.plurals, etc.),
    (sharedRes|sharedR).string.xxx, (sharedRes|sharedR).plurals.xxx, wearR.string.xxx; getString, stringResource,
    pluralStringResource, getQuantityString.
  - XML: @string/xxx, @plurals/xxx (in res/ and AndroidManifest.xml).
  - Modules are discovered automatically (any dir with src/main/res/values*/strings.xml).

Usage:
  python3 remove_unused_strings.py [--dry-run] [--modules app shared wear]

  --dry-run    Only print unused names per module; do not modify files.
  --modules    Modules to process (default: app shared wear).

Without --dry-run, unused entries are removed from all values/ and values-*/strings.xml.

Alternatives (2):

  1. Refactor Unused Resources (Android Studio)
     Safely delete unused strings across configurations.
     Select Refactor > Remove Unused Resources from the menu.
     Preview the list (including strings in values-* folders), exclude any keepers,
     then click Do Refactor. Handles strings, drawables, and more without manual edits.

  2. Gradle automation (CI/CD)
     - gradle-unused-resources-remover-plugin: add via buildscript dependencies,
       then run: ./gradlew removeUnusedResources
     - io.github.irgaly.remove-unused-resources (v2.3.0+): integrates with Lint.
       Run: ./gradlew lintDebug && ./gradlew removeUnusedResourcesDebug
       Configure exclusions (e.g. excludeNames = ["strings.xml"]) for safety
       in multi-module projects.
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------------------
# Patterns to extract string/plurals names. (?:...) is non‑capturing.
# Capture group is the name.
# Strings: R.string (module from file path); sharedRes/sharedR.string and wearR.string
# are handled in separate blocks that always add to "shared" / "wear"
PATTERNS_STRING = [re.compile(r"R\.string\.([a-zA-Z0-9_]+)")]
# Plurals: .plurals.xxx (matches R.plurals, sharedRes.plurals, wearR.plurals); module from file path
PATTERNS_PLURALS = [re.compile(r"\.plurals\.([a-zA-Z0-9_]+)")]
PATTERNS_XML_STRING = [re.compile(r'@string/([a-zA-Z0-9_]+)')]
PATTERNS_XML_PLURALS = [re.compile(r'@plurals/([a-zA-Z0-9_]+)')]

# ---------------------------------------------------------------------------
# Parsing and writing strings.xml (aligned with translate.parse_resources)

_PLURAL_QUANTITY_ORDER = ("zero", "one", "two", "few", "many", "other")


def _iter_plural_quantities(items_dict: dict) -> list:
    seen = set()
    for q in _PLURAL_QUANTITY_ORDER:
        if q in items_dict:
            seen.add(q)
            yield q
    for q in sorted(items_dict):
        if q not in seen:
            yield q


def parse_resources(file_path: Path) -> list[dict]:
    """Parse strings.xml: <string> and <plurals> in document order."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        items = []
        for child in root:
            if child.tag == "string":
                name = child.get("name")
                translatable = child.get("translatable", "true")
                text = child.text or ""
                items.append({
                    "type": "string",
                    "name": name,
                    "text": text,
                    "translatable": (translatable == "true"),
                    "attrs": {k: v for k, v in child.items() if k != "name"},
                })
            elif child.tag == "plurals":
                name = child.get("name")
                translatable = child.get("translatable", "true")
                plural_items = {}
                for item_elem in child.findall("item"):
                    q = item_elem.get("quantity")
                    if q:
                        plural_items[q] = item_elem.text or ""
                items.append({
                    "type": "plurals",
                    "name": name,
                    "items": plural_items,
                    "translatable": (translatable == "true"),
                    "attrs": {k: v for k, v in child.items() if k != "name"},
                })
        return items
    except ET.ParseError as e:
        print(f"Error parsing {file_path}: {e}", file=sys.stderr)
        return []


def _escape_text(text: str) -> str:
    if text is None:
        return ""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\\'", "'")
        .replace("'", "\\'")
        .replace("...", "…")
    )


def write_resources(file_path: Path, items: list[dict]) -> None:
    """Write strings.xml with the given string and plurals items (no merge)."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
    for item in items:
        name = item["name"]
        attrs = item.get("attrs", {})
        attr_part = " " + " ".join(f'{k}="{v}"' for k, v in attrs.items()) if attrs else ""

        if item.get("type") == "plurals":
            lines.append(f'    <plurals name="{name}"{attr_part}>')
            for q in _iter_plural_quantities(item.get("items", {})):
                text = item["items"][q]
                lines.append(f'        <item quantity="{q}">{_escape_text(text)}</item>')
            lines.append("    </plurals>")
        else:
            text = item.get("text") or ""
            lines.append(f'    <string name="{name}"{attr_part}>{_escape_text(text)}</string>')
    lines.append("</resources>")
    file_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Module discovery and scanning

def discover_modules(project_root: Path) -> list[str]:
    """Find all modules that have values/ or values-*/strings.xml under src/main/res."""
    found = []
    for d in sorted(project_root.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        res = d / "src" / "main" / "res"
        if not res.exists():
            continue
        if (res / "values" / "strings.xml").exists():
            found.append(d.name)
        else:
            for c in res.iterdir():
                if c.is_dir() and c.name.startswith("values-") and (c / "strings.xml").exists():
                    found.append(d.name)
                    break
    return found


def scan_used(project_root: Path) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """
    Scan all modules with res/values*/strings.xml. Return (used_strings, used_plurals).
    Each value: {module: set of names}.
    """
    modules = discover_modules(project_root)
    used_strings: dict[str, set[str]] = {m: set() for m in modules}
    used_plurals: dict[str, set[str]] = {m: set() for m in modules}

    def add_string(mod: str, name: str) -> None:
        if mod in used_strings:
            used_strings[mod].add(name)

    def add_plural(mod: str, name: str) -> None:
        if mod in used_plurals:
            used_plurals[mod].add(name)

    for module in modules:
        src = project_root / module / "src"
        if not src.exists():
            continue
        for f in src.rglob("*.kt"):
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            posix = f.as_posix()
            for line in text.splitlines():
                if line.strip().startswith("//"):
                    continue
                for pat in PATTERNS_STRING:
                    for m in pat.finditer(line):
                        n = m.group(1)
                        for mod in modules:
                            if f"/{mod}/" in posix:
                                add_string(mod, n)
                                break
                for pat in PATTERNS_PLURALS:
                    for m in pat.finditer(line):
                        n = m.group(1)
                        for mod in modules:
                            if f"/{mod}/" in posix:
                                add_plural(mod, n)
                                break
                # sharedRes / sharedR in app or wear -> shared
                for m in re.finditer(r"(?:sharedRes|sharedR)\.string\.([a-zA-Z0-9_]+)", line):
                    add_string("shared", m.group(1))
                for m in re.finditer(r"(?:sharedRes|sharedR)\.plurals\.([a-zA-Z0-9_]+)", line):
                    add_plural("shared", m.group(1))
                # wearR.string in wear -> wear
                for m in re.finditer(r"wearR\.string\.([a-zA-Z0-9_]+)", line):
                    add_string("wear", m.group(1))

        for f in src.rglob("*.xml"):
            posix = f.as_posix()
            # Include res XML and AndroidManifest (which can reference @string/ and @plurals/)
            if "/res/" not in posix and f.name != "AndroidManifest.xml":
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for line in text.splitlines():
                for pat in PATTERNS_XML_STRING:
                    for m in pat.finditer(line):
                        n = m.group(1)
                        for mod in modules:
                            if f"/{mod}/" in posix:
                                add_string(mod, n)
                                break
                for pat in PATTERNS_XML_PLURALS:
                    for m in pat.finditer(line):
                        n = m.group(1)
                        for mod in modules:
                            if f"/{mod}/" in posix:
                                add_plural(mod, n)
                                break

    return used_strings, used_plurals


# ---------------------------------------------------------------------------
# Main

def get_strings_files(project_root: Path, module: str) -> list[Path]:
    res = project_root / module / "src" / "main" / "res"
    if not res.exists():
        return []
    out = []
    for d in res.iterdir():
        if d.is_dir() and (d.name == "values" or d.name.startswith("values-")):
            f = d / "strings.xml"
            if f.exists():
                out.append(f)
    return sorted(out)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Remove unused string and plural resources from strings.xml"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only report unused names; do not modify files",
    )
    parser.add_argument(
        "--modules",
        nargs="+",
        default=["app", "shared", "wear"],
        metavar="M",
        help="Modules to process (default: app shared wear)",
    )
    args = parser.parse_args()

    project_root = PROJECT_ROOT
    used_strings, used_plurals = scan_used(project_root)

    total_removed = 0
    for module in args.modules:
        files = get_strings_files(project_root, module)
        if not files:
            print(f"[{module}] No values/strings.xml or values-*/strings.xml found, skipping.")
            continue

        # Defined: from values/strings.xml (canonical); if none, from first values-*
        values_file = project_root / module / "src" / "main" / "res" / "values" / "strings.xml"
        if not values_file.exists():
            values_file = next((f for f in files if "values-" in f.parent.name), None) or files[0]
        defined_items = {it["name"]: it for it in parse_resources(values_file)}
        defined_names = set(defined_items.keys())
        def_strings = {n for n, it in defined_items.items() if it.get("type") != "plurals"}
        def_plurals = {n for n, it in defined_items.items() if it.get("type") == "plurals"}

        used_s = used_strings.get(module, set())
        used_p = used_plurals.get(module, set())
        unused_strings = def_strings - used_s
        unused_plurals = def_plurals - used_p
        unused = unused_strings | unused_plurals

        if not unused:
            print(f"[{module}] All {len(defined_names)} resources are used.")
            continue

        print(f"[{module}] Unused: {len(unused)} (strings: {len(unused_strings)}, plurals: {len(unused_plurals)})")
        for n in sorted(unused):
            kind = "plurals" if n in def_plurals else "string"
            print(f"  - {kind}: {n}")

        if args.dry_run:
            total_removed += len(unused)  # count for summary
            continue

        for fp in files:
            items = parse_resources(fp)
            kept = [it for it in items if it["name"] not in unused]
            removed = len(items) - len(kept)
            if removed > 0:
                write_resources(fp, kept)
                print(f"  Updated {fp.relative_to(project_root)} (removed {removed})")
                total_removed += removed

    if args.dry_run and total_removed > 0:
        print("\n(dry-run; run without --dry-run to apply changes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
