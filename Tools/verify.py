"""Regenerate the golden data and run every stage check.

    python Tools/verify.py

Needs the Python reference environment (see Reference/README.md). Prints one
line per stage and exits non-zero if any check fails.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "Reference"

STEPS = [
    ("export", "export_goldens.py"),
    ("stage1 rgb->log_e_film", "check_stage1.py"),
    ("stage2 log_e_film->cmy_film", "check_stage2.py"),
    ("stage3 cmy_film->log_e_print", "check_stage3.py"),
    ("stage4 log_e_print->cmy_print", "check_stage4.py"),
    ("stage5 cmy_print->rgb_out", "check_stage5.py"),
]

MAX_PATTERN = re.compile(r"max[^0-9]*([0-9]+(?:\.[0-9]+)?e[-+]?[0-9]+|[0-9]+\.[0-9]+)")


def python() -> str:
    for candidate in (ROOT / "spektrafilm" / ".venv" / "Scripts" / "python.exe",
                      ROOT / "spektrafilm" / ".venv" / "bin" / "python"):
        if candidate.exists():
            return str(candidate)
    return sys.executable


def run(script: str) -> tuple[int, str]:
    environment = dict(os.environ)
    environment["PYTHONPATH"] = str(ROOT / "spektrafilm" / "src")
    environment["MPLCONFIGDIR"] = str(ROOT / ".mplcache")
    result = subprocess.run([python(), script], cwd=REFERENCE, capture_output=True,
                            text=True, env=environment)
    return result.returncode, (result.stdout or "") + (result.stderr or "")


def main() -> int:
    failures = 0
    for label, script in STEPS:
        if not (REFERENCE / script).exists():
            print(f"SKIP  {label}: {script} not found")
            continue
        code, output = run(script)
        match = MAX_PATTERN.search(output)
        shown = match.group(1) if match else "n/a"
        ok = code == 0
        print(f"{'ok  ' if ok else 'FAIL'}  {label:32s} first max {shown}")
        if not ok:
            failures += 1
            print("\n".join(output.strip().splitlines()[-6:]))

    print(f"\n{failures} failing step(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
