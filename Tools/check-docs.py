"""Check that paths mentioned in the docs actually exist.

    python Tools/check-docs.py

Docs rot silently: a renamed script or a moved file leaves a dead reference
that nobody notices until it is needed. This walks the inline code spans and
links of every markdown file and checks the ones that look like repo paths.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PREFIXES = ("Tools/", "Swift/", "App/", "docs/", "Reference/", "LICENSES/",
            ".github/", "spektrafilm/")
SUFFIXES = (".md", ".swift", ".py", ".sh", ".json", ".txt", ".yml", ".cff", ".bin")

CODE_SPAN = re.compile(r"`([^`\n]+)`")
LINK = re.compile(r"\]\(([^)\s]+)\)")


def candidates(text: str):
    for match in CODE_SPAN.finditer(text):
        yield match.group(1)
    for match in LINK.finditer(text):
        yield match.group(1)


def looks_like_path(token: str) -> bool:
    if token.startswith(("http://", "https://", "#", "mailto:")):
        return False
    if "*" in token:
        return False
    if not token.endswith(SUFFIXES):
        return False
    return token.startswith(PREFIXES) or token.startswith(("../", "./"))


def main() -> int:
    markdown = sorted(ROOT.glob("*.md")) + sorted((ROOT / "docs").glob("*.md")) \
        + sorted((ROOT / "App").glob("*.md")) + sorted((ROOT / "Swift").glob("*.md")) \
        + sorted((ROOT / "Reference").glob("*.md"))

    missing: dict[str, list[str]] = {}
    checked = 0
    for path in markdown:
        base = path.parent
        for token in candidates(path.read_text(encoding="utf-8")):
            if not looks_like_path(token):
                continue
            target = token.split("#")[0].strip()
            if not target:
                continue
            # A name that starts with a known top-level directory is written
            # against the repo root; a "../x" is relative to the document.
            if token.startswith(PREFIXES):
                resolved = ROOT / target
            elif token.startswith("/"):
                resolved = pathlib.Path(target)
            else:
                resolved = base / target
            checked += 1
            if not resolved.exists() and not (path.parent / target).exists():
                missing.setdefault(token, []).append(str(path.relative_to(ROOT)))

    for token, files in sorted(missing.items()):
        print(f"MISSING {token}   (mentioned in {', '.join(files)})")

    print(f"{len(markdown)} documents, {checked} path references, {len(missing)} missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
