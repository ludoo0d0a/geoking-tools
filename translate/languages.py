"""Canonical Scora language tables (shared by i18n + Play Store tooling).

Single source of truth for Python. Keep in sync with:
  - ``build.gradle.kts`` → ``supportedLocales`` (Android resource filters)
  - ``doc/tennis-glossary.md`` → Supported languages table

``DEEPL_SUPPORTED`` is the full DeepL API catalog (superset).
``SUPPORTED_LOCALES`` / ``LANG_TO_PLAY_LOCALE`` are Scora’s app languages only.
"""

from __future__ import annotations

from typing import Optional

# ---------------------------------------------------------------------------
# Scora app languages (Android values-{code} + Play listing)
# Order matches root build.gradle.kts ``supportedLocales``.
# ---------------------------------------------------------------------------
SUPPORTED_LOCALES: list[str] = [
    "fr",
    "en",
    "da",
    "de",
    "es",
    "it",
    "ja",
    "ko",
    "nb",
    "nl",
    "pt",
    "pl",
    "ru",
    "sv",
    "tr",
    "zh",
]

# App lang → Google Play Console listing BCP-47 tag
LANG_TO_PLAY_LOCALE: dict[str, str] = {
    "en": "en-US",
    "fr": "fr-FR",
    "de": "de-DE",
    "es": "es-ES",
    "it": "it-IT",
    "pt": "pt-BR",
    "nb": "nb-NO",
    "nl": "nl-NL",
    "sv": "sv-SE",
    "da": "da-DK",
    "pl": "pl-PL",
    "ru": "ru-RU",
    "tr": "tr-TR",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "zh": "zh-CN",
}

PLAY_LOCALE_TO_LANG: dict[str, str] = {v: k for k, v in LANG_TO_PLAY_LOCALE.items()}

# Scora-specific DeepL target overrides (when base catalog code is wrong for us)
DEEPL_TARGET_OVERRIDES: dict[str, str] = {
    "pt": "PT-BR",
    "pt-br": "PT-BR",
    "pt-pt": "PT-PT",
    "en-us": "EN-US",
    "en-gb": "EN-GB",
}

# ---------------------------------------------------------------------------
# Full DeepL API language catalog (not limited to Scora locales)
# https://developers.deepl.com/docs/resources/supported-languages
# ---------------------------------------------------------------------------
DEEPL_SUPPORTED: dict[str, str] = {
    "bg": "BG",
    "cs": "CS",
    "da": "DA",
    "de": "DE",
    "el": "EL",
    "en": "EN",
    "es": "ES",
    "et": "ET",
    "fi": "FI",
    "fr": "FR",
    "hu": "HU",
    "id": "ID",
    "it": "IT",
    "ja": "JA",
    "ko": "KO",
    "lt": "LT",
    "lv": "LV",
    "nb": "NB",
    "nl": "NL",
    "pl": "PL",
    "pt": "PT",
    "ro": "RO",
    "ru": "RU",
    "sk": "SK",
    "sl": "SL",
    "sv": "SV",
    "tr": "TR",
    "uk": "UK",
    "zh": "ZH",
}


def deepl_code(lang: str) -> Optional[str]:
    """Map app/BCP-47 lang code → DeepL ``source_lang`` / ``target_lang``."""
    code = (lang or "").strip().lower()
    if not code:
        return None
    if code in DEEPL_TARGET_OVERRIDES:
        return DEEPL_TARGET_OVERRIDES[code]
    base = code.split("-", 1)[0]
    if base in DEEPL_TARGET_OVERRIDES:
        return DEEPL_TARGET_OVERRIDES[base]
    return DEEPL_SUPPORTED.get(base)


def assert_locale_tables_consistent() -> None:
    """Raise if SUPPORTED_LOCALES and LANG_TO_PLAY_LOCALE diverge."""
    supported = set(SUPPORTED_LOCALES)
    play = set(LANG_TO_PLAY_LOCALE)
    if supported != play:
        raise AssertionError(
            "SUPPORTED_LOCALES and LANG_TO_PLAY_LOCALE disagree: "
            f"only_supported={sorted(supported - play)} "
            f"only_play={sorted(play - supported)}"
        )
    missing_deepl = [c for c in SUPPORTED_LOCALES if deepl_code(c) is None]
    if missing_deepl:
        raise AssertionError(f"No DeepL mapping for Scora locales: {missing_deepl}")


assert_locale_tables_consistent()
