"""Type-check the Swift core on Compiler Explorer (no local toolchain needed).

    python Tools/typecheck-remote.py [compiler-id]

The core sources are merged into one file and type-checked by a real Swift
compiler on godbolt.org. Excluded: `ImageBridge.swift` (CoreGraphics only
exists on Apple platforms) and the App target. `Bundle.module` is stubbed with
`Bundle.main` because SwiftPM generates it.

This catches type errors, not behaviour: the golden tests still need a Mac.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Swift" / "Sources" / "SpektraCore"

ORDER = [
    "MathCompat", "SRGB", "Parallel", "Colour", "ChromaTable", "Curves", "DensityModel", "Profile",
    "Golden", "BundledPack", "FilmExposure", "FilmDevelopment", "Printing",
    "Scanning", "PrintDevelopment", "Simulation", "SelfTest",
]

STUB = """
// --- test-harness stubs (SwiftPM generates Bundle.module) -------------------
extension Bundle {
    static var module: Bundle { Bundle.main }
}
// ---------------------------------------------------------------------------
"""


def merged_source(with_tests: bool = False) -> str:
    parts = ["import Foundation\n", STUB]
    for name in ORDER:
        path = SOURCES / f"{name}.swift"
        parts.append(f"\n// ===== {name}.swift =====\n")
        parts.append(path.read_text(encoding="utf-8"))

    if with_tests:
        parts.append("\nimport XCTest\n")
        for path in sorted((ROOT / "Swift" / "Tests" / "SpektraCoreTests").glob("*.swift")):
            text = path.read_text(encoding="utf-8")
            text = "\n".join(
                line for line in text.splitlines()
                if not line.startswith("@testable import")
            )
            parts.append(f"\n// ===== {path.name} =====\n")
            parts.append(text)
    return "".join(parts)


def compile_remotely(source: str, compiler: str) -> dict:
    body = {
        "source": source,
        "options": {
            "userArguments": "-typecheck -swift-version 5",
            "filters": {"binary": False, "execute": False, "labels": True},
        },
    }
    request = urllib.request.Request(
        f"https://godbolt.org/api/compiler/{compiler}/compile",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    arguments = [a for a in sys.argv[1:] if not a.startswith("-")]
    with_tests = "--with-tests" in sys.argv
    compiler = arguments[0] if arguments else "swift603"
    source = merged_source(with_tests=with_tests)
    print(f"checking {len(source)} bytes with {compiler}"
          + (" (sources + tests)" if with_tests else " (sources)"))

    result = compile_remotely(source, compiler)
    code = result.get("code", -1)
    stderr = result.get("stderr") or []
    lines = [entry.get("text", "") for entry in stderr]

    errors = [line for line in lines if ": error:" in line]
    print(f"exit code {code}, {len(errors)} error line(s)")

    for line in lines:
        print(line)
    return 0 if code == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

