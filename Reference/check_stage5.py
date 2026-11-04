"""Validate the stage-5 spec (print density -> output RGB) in numpy.

    python check_stage5.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_stage1 as c  # noqa: E402


def srgb_encode(x: np.ndarray) -> np.ndarray:
    # IEC 61966-2-1
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def main() -> int:
    _, arrays = c.load()
    cmy = arrays["taps.cmy_print"].astype(np.float64)
    expected = arrays["taps.rgb_out"].astype(np.float64)

    channel_density = arrays["setup.print.channel_density"].astype(np.float64)
    base_density = arrays["setup.print.base_density"].astype(np.float64)
    illum = arrays["setup.scan.illuminant"].astype(np.float64)
    cmfs = arrays["setup.scan.cmfs"].astype(np.float64)
    norm = float(arrays["setup.scan.normalization"][0])
    M = arrays["setup.scan.xyz_to_rgb"].astype(np.float64)
    R = arrays["setup.scan.roundtrip_matrix"].astype(np.float64)
    print("roundtrip matrix\n", np.round(R, 8))

    density_spectral = cmy @ channel_density.T + base_density
    light = 10.0 ** (-density_spectral) * illum
    light[np.isnan(light)] = 0.0
    xyz = (light @ cmfs) / norm

    # `XYZ_to_RGB(eye)` stores XYZ on the rows: rgb = M^T * xyz.
    rgb = xyz @ M
    results = {}
    for label, matrix in (("roundtrip", R), ("no roundtrip", None)):
        value = rgb if matrix is None else rgb @ matrix
        out = srgb_encode(value)
        d = np.abs(out - expected)
        results[label] = d.max()
        print(f"{label:14s} max {d.max():.3e}  mean {d.mean():.3e}")
    return 0 if results["roundtrip"] < 1e-6 else 1


if __name__ == "__main__":
    raise SystemExit(main())
