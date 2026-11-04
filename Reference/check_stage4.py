"""Validate the stage-4 spec (paper exposure -> print density) in numpy.

    python check_stage4.py

The print's characteristic curves are *evaluated* from the fitted model
(`density_curves_model`, three normal CDFs per channel), not read from the
stored 256-sample array.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy.special import erf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_stage1 as c  # noqa: E402
import check_stage2 as c2  # noqa: E402


def layer_cdf(z: np.ndarray, positive: bool) -> np.ndarray:
    signed = -z if positive else z
    return 0.5 * (1.0 + erf(signed / np.sqrt(2.0)))


def evaluate_channel(x, centers, amplitudes, sigmas, positive):
    total = np.zeros_like(x)
    for i in range(len(centers)):
        z = (x - centers[i]) / sigmas[i]
        total += amplitudes[i] * layer_cdf(z, positive)
    return total


def evaluate_model(x, model, positive):
    return np.stack([evaluate_channel(x, model["centers"][ch],
                                      model["amplitudes"][ch],
                                      model["sigmas"][ch], positive)
                     for ch in range(3)], axis=-1)


def main() -> int:
    _, arrays = c.load()
    profile = json.loads((Path("..") / "spektrafilm" / "src" / "spektrafilm" / "data"
                         / "profiles" / "kodak_portra_endura.json").read_text())
    model = profile["data"]["density_curves_model"]
    print("model type:", model["model_type"], "layers:", len(model["centers"][0]))

    log_e = arrays["taps.log_e_print"].astype(np.float64)
    expected = arrays["taps.cmy_print"].astype(np.float64)
    log_exposure = arrays["setup.print.log_exposure"].astype(np.float64)

    curves = evaluate_model(log_exposure, model, positive=False)
    axis = np.repeat(log_exposure[:, None], 3, axis=1)
    cmy = c2.fast_interp(log_e, axis, curves)

    diff = np.abs(cmy - expected)
    print(f"cmy_print from evaluated model: max {diff.max():.3e}  mean {diff.mean():.3e}")

    stored = arrays["setup.print.density_curves"].astype(np.float64)
    print("max |evaluated - stored|:", np.abs(curves - stored).max())
    return 0 if diff.max() < 1e-6 else 1


if __name__ == "__main__":
    raise SystemExit(main())
