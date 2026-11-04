"""Sanity checks for the Swift sources, runnable without a Mac.

    python Tools/check-sources.py

Swift has no compiler here, so this catches the two failures that have already
bitten: a source file written in a non-UTF-8 encoding (PowerShell's default on
Windows) and unbalanced delimiters from a bad bulk edit.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRECTORIES = ["Swift", "App"]


def strip_noise(source: str) -> str:
    source = re.sub(r"//[^\n]*", "", source)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', source)


def main() -> int:
    files = []
    for directory in DIRECTORIES:
        files += sorted((ROOT / directory).rglob("*.swift"))

    failures = 0
    for path in files:
        relative = path.relative_to(ROOT)
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            print(f"ENCODING {relative}: not UTF-8 ({error})")
            failures += 1
            continue
        if text.startswith("\ufeff"):
            print(f"ENCODING {relative}: UTF-8 BOM")
            failures += 1

        stripped = strip_noise(text)
        for opening, closing in ("()", "{}", "[]"):
            if stripped.count(opening) != stripped.count(closing):
                print(f"BALANCE  {relative}: {opening}{closing} "
                      f"{stripped.count(opening)}/{stripped.count(closing)}")
                failures += 1

    print(f"{len(files)} files checked, {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
