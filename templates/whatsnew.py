#!/usr/bin/env python3
"""Thin wrapper — delegates to geoking-tools/bin/whatsnew.py."""
import os
import runpy
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("GEOKING_PROJECT_ROOT", ROOT)

for candidate in (
    os.environ.get("GEOKING_TOOLS"),
    os.path.join(ROOT, "..", "geoking-tools"),
    os.path.expanduser("~/dev/android/geoking-tools"),
):
    if candidate and os.path.isdir(candidate):
        script = os.path.join(candidate, "bin", "whatsnew.py")
        if os.path.isfile(script):
            sys.argv[0] = script
            runpy.run_path(script, run_name="__main__")
            raise SystemExit(0)

sys.exit("geoking-tools introuvable — clone ../geoking-tools ou exporte GEOKING_TOOLS")
