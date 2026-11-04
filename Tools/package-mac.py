"""Package the parts of this workspace a Mac needs, and nothing else.

    python Tools/package-mac.py

Produces `dist/spektra-ios-mac-<stamp>.zip` plus a SHA-256. The Python
reference checkout, the virtualenv and the uv caches stay behind: the Swift
package carries its own baked data, so the Mac can build and test with no
Python at all.
"""

from __future__ import annotations

import hashlib
import pathlib
import sys
import time
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"

# Included, in this order, relative to the workspace root.
INCLUDE = ["README.md", "STATUS.md", "NOTICE.md", "CITATION.cff", "LICENSES",
           "Swift", "App", "docs", "Tools", "Reference", ".github"]

# Never inside the archive.
EXCLUDED_DIRECTORIES = {".build", ".swiftpm", "__pycache__", ".venv", ".git",
                        "xcodeproj", "xcuserdata", "DerivedData"}
EXCLUDED_SUFFIXES = {".pyc", ".zip", ".log"}
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db", ".gitignore"}


def wanted(path: pathlib.Path) -> bool:
    if any(part in EXCLUDED_DIRECTORIES for part in path.parts):
        return False
    if path.name in EXCLUDED_NAMES or path.suffix in EXCLUDED_SUFFIXES:
        return False
    return True


def collect() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for entry in INCLUDE:
        target = ROOT / entry
        if target.is_file():
            files.append(target)
            continue
        for path in sorted(target.rglob("*")):
            if path.is_file() and wanted(path.relative_to(ROOT)):
                files.append(path)
    return files


def main() -> int:
    files = collect()
    if not files:
        print("nothing to package")
        return 1

    DIST.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d")
    archive = DIST / f"spektra-ios-mac-{stamp}.zip"

    total = 0
    lines = []
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in files:
            relative = path.relative_to(ROOT).as_posix()
            data = path.read_bytes()
            total += len(data)
            lines.append(f"{hashlib.sha256(data).hexdigest()}  {len(data):>9}  {relative}")
            bundle.writestr(relative, data)
        bundle.writestr("MANIFEST.sha256", "\n".join(lines) + "\n")

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / f"{archive.name}.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")

    size = archive.stat().st_size
    by_area: dict[str, int] = {}
    for path in files:
        top = path.relative_to(ROOT).parts[0]
        by_area[top] = by_area.get(top, 0) + path.stat().st_size

    print(f"{archive.name}")
    print(f"  {len(files)} files, {total/1e6:.2f} MB unpacked, {size/1e6:.2f} MB zipped")
    for area, area_size in sorted(by_area.items()):
        print(f"  {area:10s} {area_size/1e6:6.2f} MB")
    print(f"  sha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

