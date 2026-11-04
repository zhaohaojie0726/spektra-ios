"""Bake film packs and prove each one replays the reference pipeline.

    python bake_packs.py

Writes `Swift/Sources/SpektraCore/Resources/packs/<film>__<paper>/`.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import packlib  # noqa: E402

PAIRS = [
    ("kodak_portra_400", "kodak_portra_endura"),
    ("kodak_portra_800", "kodak_portra_endura"),
    ("kodak_ektar_100", "kodak_portra_endura"),
]

OUT = ROOT / "Swift" / "Sources" / "SpektraCore" / "Resources"
PROFILES = ROOT / "spektrafilm" / "src" / "spektrafilm" / "data" / "profiles"


def synthetic_image(height: int = 24, width: int = 32) -> np.ndarray:
    rng = np.random.default_rng(11)
    patches = rng.uniform(0.0, 1.0, size=(6, 8, 3))
    patches[0, 0] = (0.0, 0.0, 0.0)
    patches[0, 1] = (0.18, 0.18, 0.18)
    patches[0, 2] = (1.0, 1.0, 1.0)
    image = np.repeat(np.repeat(patches, height // 6, axis=0), width // 8, axis=1)
    return image[:height, :width]


def main() -> int:
    image = synthetic_image()
    failures = 0

    for film, paper in PAIRS:
        identifier = f"{film}__{paper}"
        # Display P3 is what an iPhone photo decodes into; the chroma table is
        # indexed by chromaticity and is input-space independent, so only the
        # 3x3 matrix differs from the sRGB bake.
        arrays, meta, params, pipeline = packlib.build(film, paper, input_space="Display P3")
        expected = pipeline.process(image)
        got = packlib.render(arrays, params, image)
        difference = float(np.abs(got - expected).max())

        pack_dir = OUT / "packs" / identifier
        packlib.write_pack(arrays, meta, pack_dir)

        # read it back the way Swift will, then replay again
        reloaded, reloaded_meta = packlib.read_pack(pack_dir)
        replay = packlib.render(reloaded, params, image)
        replay_difference = float(np.abs(replay - expected).max())

        for stock in (film, paper):
            source = PROFILES / f"{stock}.json"
            target = OUT / "profiles" / f"{stock}.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.stat().st_size != source.stat().st_size:
                shutil.copyfile(source, target)

        size = (pack_dir / "arrays.bin").stat().st_size
        ok = difference < 1e-5 and replay_difference < 1e-5
        failures += 0 if ok else 1
        print(f"{'ok  ' if ok else 'FAIL'} {identifier:44s} "
              f"render {difference:.2e}  reload {replay_difference:.2e}  {size/1e6:.2f} MB")

    print(f"\n{failures} failing pack(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
