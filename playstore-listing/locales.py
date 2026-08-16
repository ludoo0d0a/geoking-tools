"""Play Store listing constants — locale tables come from ``i18n/languages.py``."""

from __future__ import annotations

import sys
from pathlib import Path

_I18N_DIR = Path(__file__).resolve().parents[2] / "i18n"
if str(_I18N_DIR) not in sys.path:
    sys.path.insert(0, str(_I18N_DIR))

from languages import (  # noqa: E402
    LANG_TO_PLAY_LOCALE,
    PLAY_LOCALE_TO_LANG,
    SUPPORTED_LOCALES,
)

# Play Store character limits
TITLE_MAX = 30
SHORT_MAX = 80
FULL_MAX = 4000

# Wear framed screenshots for the listing (order = Play Console order)
WEAR_SCREENSHOTS: list[str] = [
    "start.png",
    "match.png",
    "tiebreak.png",
    "selection_judge_side.png",
    "selection_service_side.png",
    "end_win.png",
    "settings_format.png",
    "history.png",
]

# Phone companion screenshots (prefer higher-res JPGs when present)
PHONE_SCREENSHOTS: list[str] = [
    "phone-installed.jpg",
    "phone-connect.jpg",
    "phone-notconnected.jpg",
    "history.png",
    "history_detail.png",
]

# Loanwords that must not be "translated" into rest/timeout words
FORBIDDEN_BREAK_TRANSLATIONS = (
    "pause",
    "pausa",
    "interruption",
    "休憩",
    "休息",
)

__all__ = [
    "SUPPORTED_LOCALES",
    "LANG_TO_PLAY_LOCALE",
    "PLAY_LOCALE_TO_LANG",
    "TITLE_MAX",
    "SHORT_MAX",
    "FULL_MAX",
    "WEAR_SCREENSHOTS",
    "PHONE_SCREENSHOTS",
    "FORBIDDEN_BREAK_TRANSLATIONS",
]
