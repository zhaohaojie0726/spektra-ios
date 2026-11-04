"""Validate the stage-1 spec by transliterating it in numpy.

If this matches `taps.log_e_film` to float32 noise, then the Swift
implementation of the same formulas will too -- the only remaining risk is
typos, not misunderstanding of the reference.

    python check_stage1.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
GOLD = HERE / "goldens"

MITCHELL_B = 1.0 / 3.0
MITCHELL_C = 1.0 / 3.0


def load() -> tuple[dict, dict[str, np.ndarray]]:
    manifest = json.loads((GOLD / "manifest.json").read_text())
    blob = np.fromfile(GOLD / "arrays.bin", dtype="<f4")
    arrays = {}
    for name, entry in manifest["arrays"].items():
        off = entry["offset"]
        n = int(np.prod(entry["shape"]))
        arrays[name] = blob[off:off + n].reshape(entry["shape"])
    return manifest, arrays


def mitchell_weight(t: np.ndarray) -> np.ndarray:
    B, C = MITCHELL_B, MITCHELL_C
    x = np.abs(t)
    w = np.zeros_like(x)
    m1 = x < 1
    w[m1] = (1 / 6) * ((12 - 9 * B - 6 * C) * x[m1] ** 3
                       + (-18 + 12 * B + 6 * C) * x[m1] ** 2
                       + (6 - 2 * B))
    m2 = (x >= 1) & (x < 2)
    w[m2] = (1 / 6) * ((-B - 6 * C) * x[m2] ** 3
                       + (6 * B + 30 * C) * x[m2] ** 2
                       + (-12 * B - 48 * C) * x[m2]
                       + (8 * B + 24 * C))
    return w


def safe_index(idx: int, L: int) -> int:
    if idx < 0:
        return -idx
    if idx >= L:
        return 2 * (L - 1) - idx
    return idx


def clamp_coordinate(c: float, L: int) -> float:
    if not np.isfinite(c) or c <= 0.0:
        return 0.0
    upper = float(L - 1)
    return upper if c >= upper else c


def base_fraction(c: float, L: int) -> tuple[int, float]:
    c = clamp_coordinate(c, L)
    if c >= float(L - 1):
        return L - 2, 1.0
    base = int(np.floor(c))
    return base, c - base


def lut_lookup(lut: np.ndarray, u: float, v: float) -> np.ndarray:
    n = lut.shape[0]
    bx, fx = base_fraction(u, n)
    by, fy = base_fraction(v, n)
    wx = mitchell_weight(np.array([fx + 1, fx, fx - 1, fx - 2]))
    wy = mitchell_weight(np.array([fy + 1, fy, fy - 1, fy - 2]))
    out = np.zeros(lut.shape[2])
    wsum = 0.0
    for i in range(4):
        xi = safe_index(bx - 1 + i, n)
        for j in range(4):
            yj = safe_index(by - 1 + j, n)
            w = wx[i] * wy[j]
            wsum += w
            out += w * lut[xi, yj]
    if wsum != 0.0:
        out /= wsum
    return out


def stage1(rgb: np.ndarray, M: np.ndarray, lut: np.ndarray) -> np.ndarray:
    n = lut.shape[0]
    h, w, _ = rgb.shape
    out = np.zeros_like(rgb)
    for i in range(h):
        for j in range(w):
            p = rgb[i, j].astype(np.float64)
            # `colour.RGB_to_XYZ(np.eye(3))` returns M with RGB on the rows:
            # XYZ = M.T @ rgb.  (Verified against RGB_to_XYZ on a pixel.)
            xyz = M.T @ p
            b = float(np.sum(xyz))
            denom = max(b, 1e-10)
            x, y = xyz[0] / denom, xyz[1] / denom
            s = 1.0 - x
            tx = min(max(s * s, 0.0), 1.0)
            ty = min(max(y / max(s, 1e-10), 0.0), 1.0)
            raw = lut_lookup(lut, tx * (n - 1), ty * (n - 1)) * b
            out[i, j] = np.log10(np.maximum(raw, 0.0) + 1e-10)
    return out


def main() -> int:
    _, arrays = load()
    rgb = arrays["input.rgb"]
    expected = arrays["taps.log_e_film"]
    M = arrays["setup.colour_matrix_input_to_xyz"].astype(np.float64)
    lut = arrays["setup.tc_lut"].astype(np.float64)
    print("matrix\n", M)
    print("lut", lut.shape)

    got = stage1(rgb, M, lut)
    diff = np.abs(got - expected)
    print(f"max abs diff {diff.max():.3e}  mean {diff.mean():.3e}")
    idx = np.unravel_index(np.argmax(diff), diff.shape)
    print("worst at", idx, "got", got[idx], "want", expected[idx])
    return 0 if diff.max() < 1e-5 else 1


if __name__ == "__main__":
    raise SystemExit(main())
