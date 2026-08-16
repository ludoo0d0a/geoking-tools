#!/usr/bin/env python3
"""
Generate translated strings.xml files for each module and languages.

This script supports two modes:

1. BACK-TRANSLATION (default): Translates localized strings back to English
   - Scans values-*/strings.xml files
   - Outputs to draft/{module}/{lang}-to-en/strings.xml

2. FORWARD-TRANSLATION: Translates strings from the default (or specified) source to other languages
   - Uses values/strings.xml (default Android resources) as source by default; no values-en. Default is assumed to be English for translator services.
   - Outputs to {module}/src/main/res/values-{lang}/strings.xml

Translation backend: LibreTranslate-compatible API or DeepL API.
Configuration via environment variables:
  - LIBRETRANSLATE_URL: Base URL (default: https://libretranslate.com)
  - LIBRETRANSLATE_API_KEY: Optional API key
  - API_SLEEP_MS: Sleep between requests (default: 150ms)
  - DEEPL_API_KEY: API key for DeepL (if using provider=deepl)
  - DEEPL_API_ENDPOINT: DeepL API endpoint (default: https://api-free.deepl.com)
                        Use https://api.deepl.com for paid accounts
                        Free accounts: https://api-free.deepl.com (default)
  - DEEPL_CONTEXT: Optional DeepL translation context (influences translation but is not translated).
                   The per-language tennis glossary from doc/tennis-glossary.md is automatically
                   appended to this context for every DeepL forward/back translation, so canonical
                   tennis terms (game=jeu, break=break, etc.) bias DeepL's output.

Usage examples:
  # Back-translation (default)
  python3 translate.py --modules app shared wear
  
  # Forward translation (only missing strings, auto-detect all target languages)
  python3 translate.py --mode forward --modules app shared wear
  
  # Forward translation (only missing strings, specific languages)
  python3 translate.py --mode forward --modules app shared wear --languages de es fr
  
  # Forward translation (all strings, even existing ones)
  python3 translate.py --mode forward --modules app shared wear --languages de es fr --all-strings
  
  # Re-translate specific keys; new translations overwrite existing values in target
  python3 translate.py --mode forward --modules app shared wear --keys my_key another_key
  
  # Overwrite all existing translations
  python3 translate.py --mode forward --modules app shared wear --languages de es fr --overwrite

Notes:
  - Preserves Android placeholders like %s, %1$s, %d, %1$d during translation. Ensures they have word boundaries (adds a space when a translation glues a word to a placeholder, e.g. "Score%1$d" -> "Score %1$d").
  - Preserves \\n (and literal newlines) in translated text: they are masked with a placeholder before sending to the API and restored as \\n in the output.
  - Strings/plurals with translatable="false" are only written in the default resource file (values/strings.xml). They are omitted from locale files (values-{lang}/strings.xml) so the tag exists only once.
  - Supports <plurals> with <item quantity="one|other|zero|two|few|many">: each item is translated separately; merge and write handle plurals.
  - Default source is values/strings.xml (use --source-lang default). Default is assumed to be English for translator services (LibreTranslate, DeepL). For other codes, uses values-{lang}/strings.xml.
  - For forward translation, if no target languages are specified, auto-detects all available languages except the source language. When translating from default, English (en) is always included as a target so that values-en can be produced.
  - When writing output files, merges with existing content instead of overwriting by default. Use --overwrite to overwrite all existing translations, or --keys to overwrite specific keys.
"""

import os
import sys
import time
import json
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET
import re
from urllib import request, parse, error
from typing import Union


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKING_DIR = "i18n"
I18N_DIR = PROJECT_ROOT / WORKING_DIR
I18N_ENV_PATH = I18N_DIR / ".env"
# One markdown file per target language under i18n/glossary/{lang}.md. The
# loader extracts the content between the deepl:context:start / :end markers
# and sends it as DeepL `context` (see doc/tennis-glossary.md for the format).
GLOSSARY_DIR = PROJECT_ROOT / WORKING_DIR / "glossary"
GLOSSARY_MARKER_START = "<!-- deepl:context:start -->"
GLOSSARY_MARKER_END = "<!-- deepl:context:end -->"
# Soft cap on DeepL `context` size (DeepL has no hard limit, but context chars
# are billed). 2000 chars comfortably fits any single per-language glossary
# block plus a short base context like "tennis, match, scoreboard".
DEEPL_CONTEXT_MAX_CHARS = 2000

PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?[sd]\b")

# Placeholder used to preserve \n during translation (APIs may drop or alter literal \n)
NEWLINE_PLACEHOLDER = "\uE000"  # Private Use Area character, not in normal text


def mask_newlines_for_translation(text: str) -> str:
    """Replace newline chars and \\n escape sequence with a placeholder so translation APIs preserve line breaks."""
    if not text:
        return text
    # Replace two-char \n (backslash + n) first, then literal newline
    return text.replace("\\n", NEWLINE_PLACEHOLDER).replace("\n", NEWLINE_PLACEHOLDER)


def unmask_newlines_after_translation(text: str) -> str:
    """Restore \\n (Android escape) in translated text."""
    if not text:
        return text
    return text.replace(NEWLINE_PLACEHOLDER, "\\n")


_GLOSSARY_CACHE: dict = {}


def _read_glossary_file(code: str) -> Union[str, None]:
    """Read ``i18n/glossary/{code}.md`` and return the content between the
    ``deepl:context:start`` / ``deepl:context:end`` markers (None if the file
    or markers are missing). Result is cached per language code."""
    if code in _GLOSSARY_CACHE:
        return _GLOSSARY_CACHE[code]
    path = GLOSSARY_DIR / f"{code}.md"
    if not path.exists():
        _GLOSSARY_CACHE[code] = None
        return None
    try:
        content = path.read_text(encoding="utf-8")
    except Exception:
        _GLOSSARY_CACHE[code] = None
        return None
    start = content.find(GLOSSARY_MARKER_START)
    end = content.find(GLOSSARY_MARKER_END)
    if start < 0 or end < 0 or end <= start:
        _GLOSSARY_CACHE[code] = None
        return None
    body = content[start + len(GLOSSARY_MARKER_START):end].strip()
    result = body or None
    _GLOSSARY_CACHE[code] = result
    return result


def load_glossary_for_lang(target_lang: str) -> str:
    """Return the compact tennis glossary block for ``target_lang`` (empty
    string if none). Looks up ``i18n/glossary/{lang}.md`` directly, with a
    fallback to the base language code (e.g. ``pt-BR`` -> ``pt``)."""
    if not target_lang:
        return ""
    code = target_lang.strip().lower()
    text = _read_glossary_file(code)
    if text:
        return text
    base = code.split("-", 1)[0]
    if base != code:
        text = _read_glossary_file(base)
        if text:
            return text
    return ""


def build_deepl_context(base_context: Union[str, None], target_lang: str) -> Union[str, None]:
    """Compose the final DeepL context for ``target_lang``.

    The per-language tennis glossary comes first (most valuable to bias the
    translation), then the generic base context (e.g. domain hint). If the
    composed string exceeds ``DEEPL_CONTEXT_MAX_CHARS`` we drop the base
    context before trimming the glossary, so canonical tennis terms are never
    the first thing sacrificed."""
    glossary = load_glossary_for_lang(target_lang)
    base = (base_context or "").strip() or None

    glossary_block = (
        f"Tennis glossary (en -> {target_lang.lower()}):\n{glossary}" if glossary else None
    )

    parts = [p for p in (glossary_block, base) if p]
    if not parts:
        return None
    composed = "\n\n".join(parts)

    if len(composed) > DEEPL_CONTEXT_MAX_CHARS and glossary_block and base:
        # Drop the base context first; glossary is more useful for terminology.
        composed = glossary_block
    if len(composed) > DEEPL_CONTEXT_MAX_CHARS:
        composed = composed[: DEEPL_CONTEXT_MAX_CHARS - 3].rstrip() + "..."
    return composed


def load_i18n_env(env_path: Union[Path, None] = None) -> None:
    """Load ``i18n/.env`` into ``os.environ`` without overriding existing vars.

    Same contract as ``source .env`` in ``translate.sh`` / ``translate-listing.sh``.
    Shared by strings.xml translation and Play Store listing translation.
    """
    path = env_path or I18N_ENV_PATH
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if value.endswith(";"):
            value = value[:-1].strip()
        value = value.strip("'").strip('"')
        if key and key not in os.environ:
            os.environ[key] = value


def resolve_deepl_api_key(cli_key: Union[str, None] = None) -> str:
    """Return DeepL API key from CLI arg, env, or ``i18n/.env``."""
    load_i18n_env()
    key = (cli_key or os.environ.get("DEEPL_API_KEY") or "").strip()
    if not key:
        raise SystemExit(
            "Missing DEEPL_API_KEY. Set it in the environment or i18n/.env "
            "(same as i18n/translate.sh)."
        )
    return key


def mask_api_key(api_key: Union[str, None]) -> str:
    """Mask an API key for display (show first 4 and last 4 characters)."""
    if not api_key:
        return "(not set)"
    if len(api_key) <= 8:
        return "****"  # Too short to show anything
    return f"{api_key[:4]}...{api_key[-4:]}"


def format_http_error(e: error.HTTPError, provider: str, api_key: Union[str, None] = None) -> str:
    """Build a user-friendly message for HTTP errors from translation APIs."""
    code = e.code
    reason = e.reason or "Unknown"
    try:
        body = e.read().decode("utf-8", errors="replace").strip()
    except Exception:
        body = ""
    base = f"HTTP {code} {reason}"
    
    # For 4xx errors, include masked API key info
    key_info = ""
    if 400 <= code < 500:
        masked_key = mask_api_key(api_key)
        key_info = f" API key used: {masked_key}."
    
    # Try to parse JSON error response for more details
    error_detail = ""
    if body:
        try:
            error_obj = json.loads(body)
            if isinstance(error_obj, dict):
                if "message" in error_obj:
                    error_detail = f" Message: {error_obj['message']}"
                elif "error" in error_obj:
                    error_detail = f" Error: {error_obj['error']}"
        except Exception:
            pass
    
    if provider == "LibreTranslate":
        if code in (400, 401, 403):
            return (
                f"{base}.{key_info}{error_detail} LibreTranslate requires an API key for the public instance (libretranslate.com). "
                "Set LIBRETRANSLATE_API_KEY or use --libre-api-key. "
                "Use a self-hosted instance (--base-url) to avoid keys. See https://portal.libretranslate.com/"
            )
        if code == 429:
            return f"{base}. Rate limited. Increase --sleep-ms or reduce --batch-size."
    elif provider == "DeepL":
        if code == 403:
            return (
                f"{base}.{key_info}{error_detail} Check DEEPL_API_KEY: the key may be invalid, expired, or the DeepL API may be blocking requests. "
                "If you have a paid account, ensure you're using the correct endpoint (api.deepl.com vs api-free.deepl.com)."
            )
        if code == 401:
            return f"{base}.{key_info}{error_detail} Invalid API key. Set DEEPL_API_KEY or check --deepl-api-key."
        if code == 400:
            return f"{base}.{key_info}{error_detail} Bad request. Check parameters (source_lang, target_lang, text)."
        if code == 429:
            return f"{base}. Rate limited. Increase --sleep-ms or reduce --batch-size."
    if code >= 500:
        return f"{base}. The translation service may be temporarily unavailable. Retry later.{error_detail}"
    if body:
        # Show full response if not already parsed
        if not error_detail:
            return f"{base}.{key_info} Response: {body[:300]}"
        else:
            return f"{base}.{key_info}{error_detail} Full response: {body[:200]}"
    return base + key_info


def split_text_with_placeholders(text: str):
    parts = []
    last = 0
    for m in PLACEHOLDER_PATTERN.finditer(text):
        if m.start() > last:
            parts.append(("text", text[last:m.start()]))
        parts.append(("ph", m.group(0)))
        last = m.end()
    if last < len(text):
        parts.append(("text", text[last:]))
    return parts


def join_parts(parts):
    return "".join(p for _, p in parts)


# Placeholder pattern for ensure_placeholder_word_boundaries (no \b so we also fix glued text like "%1$dpoints")
_PH = r"%(?:\d+\$)?[sd]"


def ensure_placeholder_word_boundaries(text: str) -> str:
    """Ensure placeholders like %1$d, %2$s have word boundaries: add a space when adjacent to a word character."""
    if not text:
        return text
    # Before: "Score%1$d" -> "Score %1$d"
    text = re.sub(rf"(\w)({_PH})", r"\1 \2", text)
    # After: "%1$dpoints" -> "%1$d points"
    text = re.sub(rf"({_PH})(\w)", r"\1 \2", text)
    return text


def detect_languages_for_module(module_dir: Path):
    """Detect available languages in a module's values-* directories."""
    res_dir = module_dir / "src/main/res"
    langs = {}
    if not res_dir.exists():
        return langs
    for child in res_dir.iterdir():
        if child.is_dir() and child.name.startswith("values-"):
            lang_tag = child.name[len("values-"):]
            strings_file = child / "strings.xml"
            if strings_file.exists():
                # Extract base language (strip -rREGION etc.)
                base_lang = lang_tag.split("-r")[0]
                langs[base_lang] = strings_file
    return langs


def get_source_file_for_module(module_dir: Path, source_lang: str):
    """Get the source file for a module. Default source uses values/ (Android default resources), not values-en. Default is assumed to be English for translator services."""
    res_dir = module_dir / "src/main/res"
    if not res_dir.exists():
        return None

    # "default" = values/ only (default Android resources; no values-en)
    if source_lang == "default":
        values_file = res_dir / "values" / "strings.xml"
        if values_file.exists():
            return values_file
        # Fallback to values-en only if values/ is missing (e.g. some modules)
        en_file = res_dir / "values-en" / "strings.xml"
        if en_file.exists():
            return en_file
        return None

    # Other languages: values-{lang}, then values/ as fallback
    lang_file = res_dir / f"values-{source_lang}" / "strings.xml"
    if lang_file.exists():
        return lang_file
    values_file = res_dir / "values" / "strings.xml"
    if values_file.exists():
        return values_file
    return None


# Canonical order for plural quantities (CLDR)
_PLURAL_QUANTITY_ORDER = ("zero", "one", "two", "few", "many", "other")


def _iter_plural_quantities(items_dict: dict) -> list:
    """Yield quantity keys in a stable order."""
    seen = set()
    for q in _PLURAL_QUANTITY_ORDER:
        if q in items_dict:
            seen.add(q)
            yield q
    for q in sorted(items_dict):
        if q not in seen:
            yield q


def parse_resources(file_path: Path) -> list[dict]:
    """Parse strings.xml: both <string> and <plurals> with <item quantity="..."> in document order."""
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
        print(f"Error parsing {file_path}: {e}")
        return []


def parse_strings(file_path: Path) -> list[dict]:
    """Parse strings.xml (legacy). Use parse_resources for strings + plurals."""
    return parse_resources(file_path)


def get_existing_string_names(module_dir: Path, target_lang: str) -> set:
    """Get the set of resource names (strings and plurals) that exist in the target file."""
    target_file = module_dir / "src/main/res" / f"values-{target_lang}" / "strings.xml"
    if not target_file.exists():
        return set()
    try:
        items = parse_resources(target_file)
        return {item["name"] for item in items}
    except Exception as e:
        print(f"Warning: Could not parse existing target file {target_file}: {e}")
        return set()


def libretranslate_translate(text: str, source: str, target: str, base_url: str, api_key: Union[str, None], timeout: float = 20.0, sleep_ms: int = 0) -> str:
    if not text:
        return text
    data = {
        "q": text,
        "source": source,
        "target": target,
        "format": "text",
    }
    if api_key:
        data["api_key"] = api_key
    payload = parse.urlencode(data).encode("utf-8")
    url = base_url.rstrip("/") + "/translate"
    req = request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except error.HTTPError as e:
        raise ValueError(format_http_error(e, "LibreTranslate", api_key)) from e
    try:
        obj = json.loads(body)
        # API may return either {"translatedText": "..."} or an array structure
        if isinstance(obj, dict) and "translatedText" in obj:
            result = obj["translatedText"]
        # Some instances return plain string
        elif isinstance(obj, str):
            result = obj
        else:
            raise ValueError("Unexpected response format")
    except Exception:
        # Fallback: treat body as text
        result = body
    
    # Sleep after request if specified
    if sleep_ms > 0:
        time.sleep(sleep_ms / 1000.0)
    
    return result


def libretranslate_translate_bulk(texts: list[str], source: str, target: str, base_url: str, api_key: Union[str, None], timeout: float = 60.0, sleep_ms: int = 0) -> list[str]:
    if not texts:
        return []
    # Try JSON array bulk first
    url = base_url.rstrip("/") + "/translate"
    payload_obj = {
        "q": texts,
        "source": source,
        "target": target,
        "format": "text",
    }
    if api_key:
        payload_obj["api_key"] = api_key
    payload_json = json.dumps(payload_obj).encode("utf-8")
    req = request.Request(url, data=payload_json, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except error.HTTPError as e:
        raise ValueError(format_http_error(e, "LibreTranslate", api_key)) from e
    try:
        obj = json.loads(body)
        # Some servers return list of strings; others list of objects
        if isinstance(obj, list):
            if all(isinstance(x, str) for x in obj):
                result = obj
            elif all(isinstance(x, dict) and "translatedText" in x for x in obj):
                result = [x["translatedText"] for x in obj]
            else:
                raise ValueError("Unexpected response format")
        elif isinstance(obj, dict) and "translatedText" in obj:
            result = [obj["translatedText"]]
        else:
            raise ValueError("Unexpected response format")
        
        # Sleep after successful bulk request
        if sleep_ms > 0:
            time.sleep(sleep_ms / 1000.0)
        
        return result
    except Exception:
        pass
    # Fallback: join with separator and single call
    sep = "<<LTSEP_5f1f4c2e>>"
    joined = sep.join(texts)
    single = libretranslate_translate(joined, source, target, base_url, api_key, timeout, sleep_ms)
    parts = single.split(sep)
    if len(parts) == len(texts):
        return parts
    # Ultimate fallback: per-text
    return [libretranslate_translate(t, source, target, base_url, api_key, timeout, sleep_ms) for t in texts]


def translate_preserving_placeholders_bulk_libre(items_parts: list[list[tuple[str, str]]], source_lang: str, target_lang: str, base_url: str, api_key: Union[str, None], batch_size: int = 50, sleep_ms: int = 0) -> list[str]:
    # Collect all text segments in order
    segments: list[str] = []
    index_map: list[tuple[int, int]] = []  # (item_idx, part_idx)
    for i, parts in enumerate(items_parts):
        for j, (kind, content) in enumerate(parts):
            if kind == "text" and content.strip():
                segments.append(mask_newlines_for_translation(content))
                index_map.append((i, j))
    
    # Translate in batches
    translated_segments = []
    total_batches = (len(segments) + batch_size - 1) // batch_size
    print(f"   🔄 Translating {len(segments)} segments in {total_batches} batches (size: {batch_size})")
    
    critical_error = False
    for i in range(0, len(segments), batch_size):
        batch_num = i // batch_size + 1
        batch = segments[i:i + batch_size]
        print(f"   📤 Batch {batch_num}/{total_batches}: {len(batch)} segments")
        try:
            batch_translated = libretranslate_translate_bulk(batch, source_lang, target_lang, base_url, api_key, sleep_ms=sleep_ms)
            translated_segments.extend(batch_translated)
            print(f"   ✅ Batch {batch_num} completed")
        except Exception as e:
            print(f"   ❌ Batch {batch_num} failed: {e}")
            print(f"   🚫 Aborting file translation (target will not be modified)")
            critical_error = True
            break

    if critical_error:
        return None  # Signal to skip this file; do not write target
    
    # Rebuild texts
    out_texts = [None] * len(items_parts)
    seg_idx = 0
    for i, parts in enumerate(items_parts):
        rebuilt: list[tuple[str, str]] = []
        for j, (kind, content) in enumerate(parts):
            if kind == "ph" or not content.strip():
                rebuilt.append((kind, content))
            else:
                raw = translated_segments[seg_idx] if seg_idx < len(translated_segments) else content
                rebuilt.append((kind, unmask_newlines_after_translation(raw)))
                seg_idx += 1
        out_texts[i] = ensure_placeholder_word_boundaries(join_parts(rebuilt))
    return out_texts


def merge_strings_with_existing(existing_items: list[dict], new_items: list[dict], overwrite: bool = False, keys_to_overwrite: Union[set[str], None] = None) -> list[dict]:
    """Merge new items with existing items. Only overwrites if overwrite=True or key is in keys_to_overwrite."""
    existing_dict = {item["name"]: item for item in existing_items}
    keys_to_overwrite = keys_to_overwrite or set()
    
    # Only overwrite existing items if overwrite is True or key is in keys_to_overwrite
    for new_item in new_items:
        item_name = new_item["name"]
        if overwrite or item_name in keys_to_overwrite or item_name not in existing_dict:
            existing_dict[item_name] = new_item
    
    # Convert back to list, maintaining original order for existing items
    result = []
    # First add existing items in their original order
    for existing_item in existing_items:
        if existing_item["name"] in existing_dict:
            result.append(existing_dict[existing_item["name"]])
            del existing_dict[existing_item["name"]]  # Remove to avoid duplicates
    
    # Then add any new items that weren't in the existing list
    for new_item in new_items:
        if new_item["name"] in existing_dict:
            result.append(existing_dict[new_item["name"]])
    
    return result


def _escape_text(text: str) -> str:
    """Escape XML special chars and apostrophes for string/plurals item content."""
    if text is None:
        return ""
    return (text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\\'", "'")
            .replace("'", "\\'")
            .replace('...', "…"))


def write_strings_xml(output_file: Path, items: list[dict], source_items: Union[list[dict], None] = None, overwrite: bool = False, keys_to_overwrite: Union[set[str], None] = None):
    """Write or merge strings/plurals to output_file. If source_items is provided and the target
    has a key with a different type (string vs plurals) than the source, the target entry is
    converted to match the source type.
    When writing to a locale file (values-*), items with translatable=\"false\" are omitted
    so they exist only in the default values/strings.xml."""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    is_default_file = output_file.parent.name == "values"

    # If file exists, merge with existing content (strings + plurals)
    existing_items = []
    if output_file.exists():
        try:
            existing_items = parse_resources(output_file)
            n_str = sum(1 for i in existing_items if i.get("type") == "string")
            n_pl = sum(1 for i in existing_items if i.get("type") == "plurals")
            print(f"   📄 Found {len(existing_items)} existing resources in {output_file.name} ({n_str} strings, {n_pl} plurals)")
        except Exception as e:
            print(f"   ⚠️  Warning: Could not parse existing file {output_file}: {e}")
            existing_items = []
    
    # Merge new items with existing ones (by name)
    if existing_items:
        merged_items = merge_strings_with_existing(existing_items, items, overwrite, keys_to_overwrite)
        new_count = len(items)
        existing_count = len(existing_items)
        merged_count = len(merged_items)
        overwritten = sum(1 for item in items if item["name"] in {e["name"] for e in existing_items})
        print(f"   🔄 Merged: {existing_count} existing + {new_count} new = {merged_count} total (overwritten: {overwritten})")
    else:
        merged_items = list(items)
        print(f"   📝 Writing {len(merged_items)} new resources")

    # For locale files (values-*), remove any entries that are translatable="false" in source
    # so the tag exists only in the default values/strings.xml.
    if not is_default_file and source_items:
        non_translatable_names = {s["name"] for s in source_items if not s.get("translatable", True)}
        if non_translatable_names:
            merged_items = [m for m in merged_items if m["name"] not in non_translatable_names]

    # Align type with source: if a key exists in target but was not in items (we didn't
    # overwrite it) and the source has a different type, convert the target entry to match.
    new_names = {i["name"] for i in items}
    source_by_name = {x["name"]: x for x in (source_items or [])}
    for i, m in enumerate(merged_items):
        if m["name"] in new_names:
            continue  # already from source, type is correct
        src = source_by_name.get(m["name"])
        if not src or src.get("type") == m.get("type"):
            continue
        # Type mismatch: convert m to match src
        if src.get("type") == "string" and m.get("type") == "plurals":
            pitems = m.get("items") or {}
            text = pitems.get("other") or next(iter(pitems.values()), "")
            merged_items[i] = {
                "type": "string", "name": m["name"], "text": text,
                "translatable": m.get("translatable", True), "attrs": m.get("attrs", {}),
            }
        elif src.get("type") == "plurals" and m.get("type") == "string":
            quantities = list(_iter_plural_quantities(src.get("items", {})))
            merged_items[i] = {
                "type": "plurals", "name": m["name"],
                "items": {q: (m.get("text") or "") for q in quantities},
                "translatable": m.get("translatable", True), "attrs": m.get("attrs", {}),
            }
    
    lines = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", "<resources>"]
    for item in merged_items:
        name = item["name"]
        attrs = item.get("attrs", {})
        attr_str = " ".join(f"{k}=\"{v}\"" for k, v in attrs.items())
        attr_part = (" " + attr_str) if attr_str else ""

        if item.get("type") == "plurals":
            lines.append(f"    <plurals name=\"{name}\"{attr_part}>")
            for q in _iter_plural_quantities(item.get("items", {})):
                text = item["items"][q]
                lines.append(f"        <item quantity=\"{q}\">{_escape_text(text)}</item>")
            lines.append("    </plurals>")
        else:
            text = item.get("text") or ""
            should_auto_close = not text
            if should_auto_close:
                lines.append(f"    <string name=\"{name}\"{attr_part} />")
            else:
                lines.append(f"    <string name=\"{name}\"{attr_part}>{_escape_text(text)}</string>")
    lines.append("</resources>")
    output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ------------------ DeepL backend ------------------
# Language tables: see languages.py (SUPPORTED_LOCALES, DEEPL_SUPPORTED, deepl_code)
from languages import DEEPL_SUPPORTED, deepl_code  # noqa: E402


def get_deepl_endpoint(api_key: str) -> str:
    """Determine the correct DeepL API endpoint based on the API key.
    
    Free API keys typically start with specific prefixes, but we try both endpoints.
    Paid accounts use api.deepl.com, free accounts use api-free.deepl.com.
    """
    # Try to detect: free keys often start with 'fx' or are shorter
    # But the most reliable way is to check the account type in DeepL portal
    # For now, default to free endpoint; user can override with env var
    endpoint = os.environ.get("DEEPL_API_ENDPOINT", "https://api-free.deepl.com")
    if endpoint.endswith("/"):
        endpoint = endpoint.rstrip("/")
    return f"{endpoint}/v2/translate"


def deepl_translate(
    text: str,
    source: str,
    target: str,
    api_key: str,
    timeout: float = 20.0,
    sleep_ms: int = 0,
    context: Union[str, None] = None,
) -> str:
    if not text:
        return text
    # DeepL endpoint - auto-detect or use configured endpoint
    url = get_deepl_endpoint(api_key)
    # Use modern DeepL API: JSON body with Authorization header
    payload_obj = {
        "text": [text],
        "target_lang": target.upper(),
    }
    # source_lang is optional - only include if specified
    if source and source.upper() != "AUTO":
        payload_obj["source_lang"] = source.upper()
    # context is optional - influences translation but is not translated
    if context:
        payload_obj["context"] = context
    
    payload_json = json.dumps(payload_obj).encode("utf-8")
    req = request.Request(url, data=payload_json, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"DeepL-Auth-Key {api_key}")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except error.HTTPError as e:
        # If 403 on free endpoint, suggest trying paid endpoint
        if e.code == 403 and "api-free" in url:
            error_msg = format_http_error(e, "DeepL", api_key)
            error_msg += " If you have a paid DeepL account, set DEEPL_API_ENDPOINT=https://api.deepl.com"
            raise ValueError(error_msg) from e
        raise ValueError(format_http_error(e, "DeepL", api_key)) from e
    obj = json.loads(body)
    translations = obj.get("translations")
    if translations and isinstance(translations, list):
        result = translations[0].get("text", text)
    else:
        result = text

    # Sleep after request if specified
    if sleep_ms > 0:
        time.sleep(sleep_ms / 1000.0)

    return result


def deepl_translate_bulk(
    texts: list[str],
    source: str,
    target: str,
    api_key: str,
    timeout: float = 60.0,
    sleep_ms: int = 0,
    context: Union[str, None] = None,
) -> list[str]:
    if not texts:
        return []
    url = get_deepl_endpoint(api_key)
    # Use modern DeepL API: JSON body with Authorization header
    payload_obj = {
        "text": texts,  # Array of strings
        "target_lang": target.upper(),
    }
    # source_lang is optional - only include if specified
    if source and source.upper() != "AUTO":
        payload_obj["source_lang"] = source.upper()
    # context is optional - influences translation but is not translated
    if context:
        payload_obj["context"] = context
    
    payload_json = json.dumps(payload_obj).encode("utf-8")
    req = request.Request(url, data=payload_json, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"DeepL-Auth-Key {api_key}")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except error.HTTPError as e:
        # If 403 on free endpoint, suggest trying paid endpoint
        if e.code == 403 and "api-free" in url:
            error_msg = format_http_error(e, "DeepL", api_key)
            error_msg += " If you have a paid DeepL account, set DEEPL_API_ENDPOINT=https://api.deepl.com"
            raise ValueError(error_msg) from e
        raise ValueError(format_http_error(e, "DeepL", api_key)) from e
    obj = json.loads(body)
    translations = obj.get("translations")
    if translations and isinstance(translations, list):
        result = [x.get("text", "") for x in translations]
    else:
        result = [""] * len(texts)

    # Sleep after successful bulk request
    if sleep_ms > 0:
        time.sleep(sleep_ms / 1000.0)

    return result


def translate_preserving_placeholders_bulk_deepl(
    items_parts: list[list[tuple[str, str]]],
    source_lang: str,
    target_lang: str,
    api_key: str,
    batch_size: int = 50,
    sleep_ms: int = 0,
    context: Union[str, None] = None,
) -> list[str]:
    segments: list[str] = []
    index_map: list[tuple[int, int]] = []
    for i, parts in enumerate(items_parts):
        for j, (kind, content) in enumerate(parts):
            if kind == "text" and content.strip():
                segments.append(mask_newlines_for_translation(content))
                index_map.append((i, j))
    
    # Translate in batches
    translated_segments = []
    total_batches = (len(segments) + batch_size - 1) // batch_size
    print(f"   🔄 Translating {len(segments)} segments in {total_batches} batches (size: {batch_size})")
    
    critical_error = False
    for i in range(0, len(segments), batch_size):
        batch_num = i // batch_size + 1
        batch = segments[i:i + batch_size]
        print(f"   📤 Batch {batch_num}/{total_batches}: {len(batch)} segments")
        try:
            batch_translated = deepl_translate_bulk(batch, source_lang, target_lang, api_key, sleep_ms=sleep_ms, context=context)
            translated_segments.extend(batch_translated)
            print(f"   ✅ Batch {batch_num} completed")
        except Exception as e:
            print(f"   ❌ Batch {batch_num} failed: {e}")
            print(f"   🚫 Aborting file translation (target will not be modified)")
            critical_error = True
            break

    if critical_error:
        return None  # Signal to skip this file; do not write target
    
    out_texts = [None] * len(items_parts)
    seg_idx = 0
    for i, parts in enumerate(items_parts):
        rebuilt: list[tuple[str, str]] = []
        for j, (kind, content) in enumerate(parts):
            if kind == "ph" or not content.strip():
                rebuilt.append((kind, content))
            else:
                raw = translated_segments[seg_idx] if seg_idx < len(translated_segments) else content
                rebuilt.append((kind, unmask_newlines_after_translation(raw)))
                seg_idx += 1
        out_texts[i] = ensure_placeholder_word_boundaries(join_parts(rebuilt))
    return out_texts


def generate_for_module(
    module: str,
    base_url: str,
    libre_api_key: Union[str, None],
    langs_filter: Union[set[str], None],
    sleep_ms: int,
    provider: str,
    deepl_key: Union[str, None],
    target_lang: str,
    batch_size: int,
    mode: str,
    source_lang: str,
    missing_only: bool = True,
    keys: Union[set[str], None] = None,
    overwrite: bool = False,
    deepl_context: Union[str, None] = None,
):
    module_dir = PROJECT_ROOT / module
    
    if mode == "back":
        # Back-translation: scan existing localized files
        lang_to_file = detect_languages_for_module(module_dir)
        if not lang_to_file:
            print(f"No localized strings found for module {module}")
            return
        print(f"Found languages for {module}: {', '.join(sorted(lang_to_file.keys()))}")
        source_langs = lang_to_file
    else:
        # Forward translation: use specified source language, translate to specified languages
        source_file = get_source_file_for_module(module_dir, source_lang)
        if not source_file:
            print(f"No source file found for module {module} (language: {source_lang})")
            return
        print(f"Using source file: {source_file}")
        
        if not langs_filter:
            # Auto-detect all available target languages (excluding source language)
            print("No target languages specified - auto-detecting all available languages")
            available_langs = detect_languages_for_module(module_dir)
            # Remove source language from available languages
            if source_lang in available_langs:
                del available_langs[source_lang]
            if not available_langs:
                print(f"No target languages found for module {module} (excluding source: {source_lang})")
                return
            langs_filter = set(available_langs.keys())
            # When translating from default (values/ = English), allow English as target so values-en can be produced
            if source_lang == "default":
                langs_filter.add("en")
            print(f"Auto-detected target languages: {', '.join(sorted(langs_filter))}")
        
        source_langs = {target_lang: source_file for target_lang in langs_filter}
        # Default (values/) is assumed to be English: pass "en" to translator services to get correct results
        api_source = "en" if source_lang == "default" else source_lang

    for lang, file_path in sorted(source_langs.items()):
        if langs_filter and lang not in langs_filter:
            continue
        
        if mode == "back":
            print(f"📦 Processing {module}:{lang} -> {target_lang} from {file_path}")
        else:
            print(f"📦 Processing {module}:{source_lang} -> {lang} from {file_path}")
            
        items = parse_resources(file_path)
        source_items = list(items)  # Full source for type alignment when merging with target
        n_str = sum(1 for i in items if i.get("type") == "string")
        n_pl = sum(1 for i in items if i.get("type") == "plurals")
        print(f"   📖 Found {len(items)} resources ({n_str} strings, {n_pl} plurals), {sum(1 for i in items if i['translatable'])} translatable")
        
        # Filter by --keys if specified (applies regardless of overwrite/missing_only)
        if mode == "forward" and keys:
            original_count = len(items)
            items = [item for item in items if item["name"] in keys]
            filtered_count = len(items)
            if filtered_count < original_count:
                print(f"   🔑 Filtered to {filtered_count} keys specified via --keys (removed {original_count - filtered_count} others)")
        
        # Filter items based on missing_only and overwrite flags (only for forward translation)
        if mode == "forward" and missing_only and not overwrite and langs_filter:
            existing_names = get_existing_string_names(module_dir, lang)
            if existing_names:
                original_count = len(items)
                # Only include missing items (keys filter already applied above)
                items = [item for item in items if item["name"] not in existing_names]
                filtered_count = len(items)
                print(f"   🔍 Filtered to {filtered_count} missing (removed {original_count - filtered_count} existing)")
        
        if not items:
            print(f"   ⏭️  No resources to translate for {module}:{lang}")
            print(f"   ⏭️ Skipped {module}:{lang}")
            print()
            continue
        
        # Build units: one per string, one per (plurals, quantity)
        units: list[tuple[int, Union[str, None], str]] = []  # (item_idx, quantity or None, text)
        for i, item in enumerate(items):
            if item.get("type") == "plurals":
                for q in _iter_plural_quantities(item.get("items", {})):
                    units.append((i, q, item["items"][q]))
            else:
                units.append((i, None, item.get("text") or ""))

        parts_per_unit: list[list[tuple[str, str]]] = []
        passthrough_flags: list[bool] = []
        for (i, _q, text) in units:
            item = items[i]
            pt = not item["translatable"]
            passthrough_flags.append(pt)
            if pt:
                parts_per_unit.append([("text", text)])
            else:
                parts_per_unit.append(split_text_with_placeholders(text))

        out_texts: list[str] = []
        if provider == "libre":
            if mode == "back":
                libre_source = lang.lower()
                libre_target = target_lang.lower()
            else:
                libre_source = api_source.lower()
                libre_target = lang.lower()
            print(f"   🌐 Using LibreTranslate ({libre_source} -> {libre_target})")
            out_texts = translate_preserving_placeholders_bulk_libre(parts_per_unit, libre_source, libre_target, base_url, libre_api_key, batch_size, sleep_ms)
        else:
            if mode == "back":
                deepl_src = deepl_code(lang)
                deepl_target = target_lang.upper()
                glossary_target = target_lang
            else:
                deepl_src = deepl_code(api_source)
                deepl_target = deepl_code(lang)
                glossary_target = lang
            
            if deepl_src is None or deepl_target is None or not deepl_key:
                print(f"   ⚠️  Skipping translation: DeepL doesn't support language or missing API key")
                print(f"   🚫 Skipping file (target will not be modified)")
                print(f"   ❌ Failed {module}:{lang}")
                print()
                continue
            deepl_endpoint = get_deepl_endpoint(deepl_key)
            endpoint_display = "free" if "api-free" in deepl_endpoint else "paid"
            print(f"   🌐 Using DeepL ({deepl_src} -> {deepl_target}) [{endpoint_display} endpoint]")
            effective_context = build_deepl_context(deepl_context, glossary_target)
            if effective_context and effective_context != (deepl_context or ""):
                glossary_only = load_glossary_for_lang(glossary_target)
                if glossary_only:
                    print(f"   📚 Loaded tennis glossary for '{glossary_target}' ({len(glossary_only)} chars)")
            out_texts = translate_preserving_placeholders_bulk_deepl(
                parts_per_unit,
                deepl_src,
                deepl_target,
                deepl_key,
                batch_size=batch_size,
                sleep_ms=sleep_ms,
                context=effective_context,
            )

        # Check if translation failed critically (returned None)
        if out_texts is None:
            print(f"   🚫 Skipping file due to critical translation errors")
            print(f"   ❌ Failed {module}:{lang}")
            print()
            continue

        # Rebuild out_items from units and out_texts
        out_items = []
        for item in items:
            out = dict(item)
            if out.get("type") == "plurals":
                out["items"] = {}
            out_items.append(out)
        for unit_idx, (i, q, text) in enumerate(units):
            # Untranslatable (translatable="false"): do not translate; write empty value in output
            res = "" if passthrough_flags[unit_idx] else out_texts[unit_idx]
            if q is None:
                out_items[i]["text"] = res
            else:
                out_items[i]["items"][q] = res

        # Determine output path based on mode
        if mode == "back":
            out_file = PROJECT_ROOT / WORKING_DIR / "draft" / module / f"{lang}-to-en" / "strings.xml"
        else:
            out_file = PROJECT_ROOT / module / "src/main/res" / f"values-{lang}" / "strings.xml"
            #out_file = PROJECT_ROOT / WORKING_DIR / "translations" / module / "src/main/res" / f"values-{lang}" / "strings.xml"

        # For locale files (values-*), omit translatable="false" items so the tag exists only in default values/
        items_to_write = out_items
        if mode == "forward" and out_file.parent.name != "values":
            items_to_write = [i for i in out_items if i.get("translatable", True)]
        
        write_strings_xml(out_file, items_to_write, source_items=source_items, overwrite=overwrite, keys_to_overwrite=keys)
        print(f"   💾 Wrote {out_file}")
        print(f"   ✅ Completed {module}:{lang}")
        print()


def test_deepl_api_key(api_key: str, endpoint: Union[str, None] = None) -> bool:
    """Test DeepL API key by translating a simple text.
    
    Returns True if successful, False otherwise.
    """
    if not api_key:
        print("❌ Error: No API key provided. Set DEEPL_API_KEY or use --deepl-api-key")
        return False
    
    print("🧪 Testing DeepL API key...")
    print(f"   API key: {mask_api_key(api_key)}")
    
    # Try using official deepl library first (if available)
    try:
        import deepl
        print("   Using official DeepL Python library")
        deepl_client = deepl.DeepLClient(api_key)
        result = deepl_client.translate_text("Hello, world!", target_lang="DE")
        print(f"   ✅ Success! Translation: {result.text}")
        print(f"   Expected: Hallo, Welt!")
        if result.text == "Hallo, Welt!":
            print("   ✅ Translation matches expected output")
        return True
    except ImportError:
        # Library not installed, use direct API call
        print("   Official library not installed, using direct API call")
        pass
    except Exception as e:
        print(f"   ⚠️  Official library error: {e}")
        print("   Falling back to direct API call...")
    
    # Fallback to direct API call
    try:
        if endpoint:
            # Temporarily override endpoint for testing
            original_endpoint = os.environ.get("DEEPL_API_ENDPOINT")
            os.environ["DEEPL_API_ENDPOINT"] = endpoint
            try:
                result = deepl_translate("Hello, world!", "EN", "DE", api_key)
            finally:
                if original_endpoint:
                    os.environ["DEEPL_API_ENDPOINT"] = original_endpoint
                elif "DEEPL_API_ENDPOINT" in os.environ:
                    del os.environ["DEEPL_API_ENDPOINT"]
        else:
            result = deepl_translate("Hello, world!", "EN", "DE", api_key)
        
        print(f"   ✅ Success! Translation: {result}")
        print(f"   Expected: Hallo, Welt!")
        if result == "Hallo, Welt!":
            print("   ✅ Translation matches expected output")
        else:
            print(f"   ⚠️  Translation differs from expected (but API call succeeded)")
        return True
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def main():
    load_i18n_env()
    parser = argparse.ArgumentParser(description="Generate translated strings.xml files using LibreTranslate or DeepL API")
    parser.add_argument("--mode", choices=["back", "forward"], default="back", help="Translation mode: back (default) or forward")
    parser.add_argument("--modules", "-m", nargs="+", default=["app", "shared", "wear"], help="Modules to process")
    parser.add_argument("--languages", "-l", nargs="*", help="Target language codes (optional - if not specified for forward mode, auto-detects all available languages except source)")
    parser.add_argument("--base-url", default=os.environ.get("LIBRETRANSLATE_URL", "https://libretranslate.com"))
    parser.add_argument("--libre-api-key", default=os.environ.get("LIBRETRANSLATE_API_KEY"))
    parser.add_argument("--sleep-ms", type=int, default=int(os.environ.get("API_SLEEP_MS", "150")))
    parser.add_argument("--provider", choices=["libre", "deepl"], default="deepl", help="Translation provider")
    parser.add_argument("--deepl-api-key", default=os.environ.get("DEEPL_API_KEY"))
    parser.add_argument("--deepl-context", default=os.environ.get("DEEPL_CONTEXT", "tennis, match, scoreboard, points counter"), help="Optional DeepL translation context (influences translation but is not translated)")
    parser.add_argument("--target-lang", default=os.environ.get("BACKTRANSLATE_TARGET_LANG", "en-us"), help="Target language for back-translation (DeepL accepts EN, EN-US, EN-GB; default: en-us)")
    parser.add_argument("--source-lang", default=os.environ.get("TRANSLATE_SOURCE_LANG", "default"), help="Source: 'default' uses values/strings.xml (assumed English for translator services); other: values-{code}/strings.xml (default: default)")
    parser.add_argument("--batch-size", type=int, default=int(os.environ.get("BACKTRANSLATE_BATCH_SIZE", "50")), help="Number of text segments per batch (default: 50)")
    parser.add_argument("--missing-only", action="store_true", default=True, help="Only translate missing strings in target languages (default: True)")
    parser.add_argument("--all-strings", action="store_true", help="Translate all strings, even if they already exist in target languages")
    parser.add_argument("--keys", nargs="*", default=None, metavar="KEY", help="Re-translate these keys even if they exist in target; new values overwrite existing")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite all existing translations, not just missing ones")
    parser.add_argument("--test", action="store_true", help="Test API key by translating 'Hello, world!' to German")
    args = parser.parse_args()
    
    # Handle test mode
    if args.test:
        if args.provider == "deepl":
            api_key = args.deepl_api_key
            endpoint = os.environ.get("DEEPL_API_ENDPOINT")
            success = test_deepl_api_key(api_key, endpoint)
            sys.exit(0 if success else 1)
        elif args.provider == "libre":
            print("❌ Test mode not yet implemented for LibreTranslate")
            sys.exit(1)
        else:
            print("❌ Test mode requires --provider deepl or --provider libre")
            sys.exit(1)

    langs_filter = set(args.languages) if args.languages else None
    
    # Handle missing_only logic - if all-strings or overwrite is specified, override missing_only
    missing_only = args.missing_only and not args.all_strings and not args.overwrite
    overwrite = args.overwrite

    keys = set(args.keys or [])

    mode_name = "Back-translation" if args.mode == "back" else "Forward translation"
    print(f"🔄 {mode_name} Generator")
    print("=" * 50)
    print(f"Mode: {args.mode}")
    print(f"Provider: {args.provider}")
    if args.provider == "deepl" and args.deepl_context:
        print(f"DeepL context: {args.deepl_context}")
    if args.mode == "back":
        print(f"Target language: {args.target_lang}")
    else:
        print(f"Source language: {args.source_lang}")
        print(f"Missing-only mode: {missing_only}")
        print(f"Overwrite mode: {overwrite}")
        if keys:
            print(f"Keys to overwrite: {', '.join(sorted(keys))}")
        if not langs_filter:
            print("Target languages: Auto-detect (all available except source)")
        else:
            print(f"Target languages: {', '.join(sorted(langs_filter))}")
    print(f"Batch size: {args.batch_size}")
    print(f"Modules: {', '.join(args.modules)}")
    print()

    for module in args.modules:
        print(f"🚀 Starting module: {module}")
        generate_for_module(module, args.base_url, args.libre_api_key, langs_filter, args.sleep_ms, args.provider, args.deepl_api_key, args.target_lang, args.batch_size, args.mode, args.source_lang, missing_only, keys, overwrite, args.deepl_context)
        print(f"🎉 Finished module: {module}")
        print()


if __name__ == "__main__":
    main()


