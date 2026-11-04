"""Validate the stage-2 spec (log exposure -> CMY density) in numpy.

    python check_stage2.py

Mirrors `develop()` in the deterministic configuration: normalized density
curves, a pointwise DIR-coupler correction (diffusion off), and a second
curve lookup.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_stage1 as c  # noqa: E402


def fast_interp(image: np.ndarray, x_axis: np.ndarray, y_vals: np.ndarray) -> np.ndarray:
    """`fast_interp`: linear, right-biased on ties, clamped outside."""
    k = x_axis.shape[0]
    out = np.empty_like(image)
    for ch in range(image.shape[2]):
        xa = x_axis[:, ch]
        for idx in np.ndindex(image.shape[0], image.shape[1]):
            x = image[idx][ch]
            if x <= xa[0]:
                out[idx][ch] = y_vals[0, ch]
            elif x >= xa[k - 1]:
                out[idx][ch] = y_vals[k - 1, ch]
            else:
                i = int(np.searchsorted(xa, x, side="right"))
                low = i - 1
                dx = xa[low + 1] - xa[low]
                t = (x - xa[low]) / dx if dx != 0 else 0.0
                out[idx][ch] = y_vals[low, ch] + t * (y_vals[low + 1, ch] - y_vals[low, ch])
    return out


def develop(log_e: np.ndarray, curves: np.ndarray, log_exposure: np.ndarray,
            couplers: np.ndarray) -> np.ndarray:
    normalized = curves - np.nanmin(curves, axis=0)
    axis = np.repeat(log_exposure[:, None], 3, axis=1)

    density = fast_interp(log_e, axis, normalized)

    # back-solved curves (no couplers yet)
    amount_curves = normalized @ couplers
    le0 = log_exposure[:, None] - amount_curves
    curves0 = np.zeros_like(normalized)
    for ch in range(3):
        curves0[:, ch] = np.interp(log_exposure, le0[:, ch], normalized[:, ch])

    log_raw0 = log_e - density @ couplers
    return fast_interp(log_raw0, axis, curves0)


def main() -> int:
    _, arrays = c.load()
    log_e = arrays["taps.log_e_film"].astype(np.float64)
    expected = arrays["taps.cmy_film"].astype(np.float64)
    curves = arrays["setup.film.density_curves"].astype(np.float64)
    log_exposure = arrays["setup.film.log_exposure"].astype(np.float64)
    couplers = arrays["setup.couplers_matrix"].astype(np.float64)
    print("couplers\n", np.round(couplers, 4))

    got = develop(log_e, curves, log_exposure, couplers)
    diff = np.abs(got - expected)
    print(f"max abs diff {diff.max():.3e}  mean {diff.mean():.3e}")
    idx = np.unravel_index(np.argmax(diff), diff.shape)
    print("worst at", idx, "got", got[idx], "want", expected[idx])
    return 0 if diff.max() < 1e-6 else 1


if __name__ == "__main__":
    raise SystemExit(main())
