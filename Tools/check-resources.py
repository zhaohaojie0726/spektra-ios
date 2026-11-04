"""Check that every array the Swift code asks for exists in the bundled golden.

    python Tools/check-resources.py

A missing name is a runtime crash inside `BundledPack.load()` that a compiler
cannot see, so it is worth catching on the machine that bakes the data.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = (pathlib.Path(sys.argv[1]) if len(sys.argv) > 1
             else ROOT / "Swift" / "Sources" / "SpektraCore" / "Resources")
SWIFT_ROOTS = [ROOT / "Swift" / "Sources", ROOT / "Swift" / "Tests"]

NAME = re.compile(r'array\("([^"]+)"\)')


def manifests() -> list[pathlib.Path]:
    return sorted(RESOURCES.rglob("manifest.json"))


def main() -> int:
    found = manifests()
    if not found:
        print(f"no manifests under {RESOURCES}")
        return 1

    available: set[str] = set()
    for manifest in found:
        available |= set(json.loads(manifest.read_text(encoding="utf-8"))["arrays"])

    requested: dict[str, list[str]] = {}
    for root in SWIFT_ROOTS:
        for path in sorted(root.rglob("*.swift")):
            for match in NAME.finditer(path.read_text(encoding="utf-8")):
                requested.setdefault(match.group(1), []).append(path.name)

    missing = {name: files for name, files in requested.items() if name not in available}
    print(f"{len(found)} manifest(s), {len(available)} arrays, {len(requested)} requested")
    for name, files in sorted(missing.items()):
        print(f"MISSING {name}  (used by {', '.join(sorted(set(files)))})")

    # Every pack must have its files and the profiles it names. A pack pointing
    # at a profile that was not shipped fails at runtime, not at compile time.
    profiles = {p.stem for p in (RESOURCES / "profiles").glob("*.json")}
    packs = sorted((RESOURCES / "packs").iterdir()) if (RESOURCES / "packs").exists() else []
    for pack in packs:
        for required in ("manifest.json", "arrays.bin", "meta.json"):
            if not (pack / required).exists():
                print(f"MISSING {pack.name}/{required}")
                missing[f"{pack.name}/{required}"] = ["pack"]
        meta_path = pack / "meta.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            for role in ("film", "paper"):
                stock = meta.get(role, "")
                if stock not in profiles:
                    print(f"MISSING profile {stock} for {pack.name} ({role})")
                    missing[f"profile:{stock}"] = [pack.name]

    print(f"{len(packs)} pack(s), {len(profiles)} profile(s)")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
