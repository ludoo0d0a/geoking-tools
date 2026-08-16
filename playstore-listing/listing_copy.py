"""Canonical English Play Store listing copy (source for DeepL).

Other languages live in ``doc/playstore/text-{lang}.md``, produced by
``listing_cli.py translate`` (reuses ``i18n/translate.py`` + tennis glossaries).
Curated overrides (e.g. French) are edited directly in those markdown files.
"""

from __future__ import annotations

from typing import TypedDict


class ListingCopy(TypedDict):
    title: str
    short_description: str
    full_description: str


# Brand name — never translated
APP_TITLE = "Scora"

SOURCE_LANG = "en"

SOURCE_COPY: ListingCopy = {
    "title": APP_TITLE,
    "short_description": "Tennis scoreboard on your Wear OS watch — score, serve & sides",
    "full_description": """Scora is a Wear OS tennis scoreboard. Track score, serve, and sides on your wrist. Focus on your game, not on points. Free to try — no ads, ever.

Scora helps you manage:
• Points, games, sets, and match score in real time
• Service side (yellow ball — deuce and advantage court)
• Player court positioning for singles and doubles
• Side change alerts with judge-chair reference
• Tie-breaks, super tie-breaks, and mega tie-breaks
• No-ad (deciding point) scoring
• Formats 1–10 and Format Chelem (FFT-style)
• Vibrations on every point
• Always-on / ambient display mode
• Post-match stats: aces, winners, double faults, unforced errors, break points

Works fully on your Wear OS watch during a match — no phone needed on court. Optional Android companion app for installation help, history, and stats sync.

100% offline during play. 100% ad-free.

Learn more: https://scorawatch.com
""",
}

# Back-compat alias used by older call sites
LISTING_COPY: dict[str, ListingCopy] = {SOURCE_LANG: SOURCE_COPY}
