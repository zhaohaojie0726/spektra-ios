"""Validate the stage-3 spec (film density -> paper exposure) in numpy.

    python check_stage3.py

Mirrors `PrintingStage.expose` with the enlarger LUT off, print exposure 1.0,
no pre-flash, no diffusion and no black/white correction.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_stage1 as c  # noqa: E402
import check_stage2 as c2  # noqa: E402


def density_to_light(density: np.ndarray, light: np.ndarray) -> np.ndarray:
    transmitted = 10.0 ** (-density)
    transmitted = transmitted * light
    transmitted[np.isnan(transmitted)] = 0.0
    return transmitted


def printing(log_e_print_density: np.ndarray,
             film_channel_density: np.ndarray,
             film_base_density: np.ndarray,
             paper_sensitivity: np.ndarray,
             filtered_illuminant: np.ndarray,
             midgray_density: np.ndarray) -> np.ndarray:
    h, w, _ = log_e_print_density.shape

    # spectral density of the negative for every pixel: (H,W,81)
    density_spectral = log_e_print_density @ film_channel_density.T + film_base_density
    light = density_to_light(density_spectral, filtered_illuminant)
    raw = light @ paper_sensitivity

    light_mid = density_to_light(midgray_density, filtered_illuminant)  # (81,)
    raw_mid = light_mid @ paper_sensitivity                             # (3,)
    raw_mid = np.fmax(raw_mid, 1e-10)
    geometric_mean = np.exp(np.mean(np.log(raw_mid), axis=0))  # (3,)
    raw = raw * (1.0 / geometric_mean)

    return np.log10(np.fmax(raw, 0.0) + 1e-10)


def main() -> int:
    _, arrays = c.load()
    cmy_film = arrays["taps.cmy_film"].astype(np.float64)
    expected = arrays["taps.log_e_print"].astype(np.float64)

    got = printing(
        cmy_film,
        arrays["setup.film.channel_density"].astype(np.float64),
        arrays["setup.film.base_density"].astype(np.float64),
        10 ** np.nan_to_num(arrays["setup.print.log_sensitivity"].astype(np.float64)),
        arrays["setup.enlarger.filtered_illuminant"].astype(np.float64),
        arrays["setup.enlarger.density_spectral_midgray"].astype(np.float64),
    )
    diff = np.abs(got - expected)
    print(f"log_e_print: max abs diff {diff.max():.3e}  mean {diff.mean():.3e}")

    # print density: does the stored curve equal the evaluated model?
    curves = arrays["setup.print.density_curves"].astype(np.float64)
    log_exposure = arrays["setup.print.log_exposure"].astype(np.float64)
    expected_print = arrays["taps.cmy_print"].astype(np.float64)
    axis = np.repeat(log_exposure[:, None], 3, axis=1)
    cmy = c2.fast_interp(got, axis, curves)
    d2 = np.abs(cmy - expected_print)
    print(f"cmy_print (raw curves): max {d2.max():.3e}")
    normalized = curves - np.nanmin(curves, axis=0)
    cmy_n = c2.fast_interp(got, axis, normalized)
    d3 = np.abs(cmy_n - expected_print)
    print(f"cmy_print (normalised): max {d3.max():.3e}")
    # The print's curves come from the fitted model, not from these samples;
    # both controls above are expected to be large. Only the spectral integral
    # is asserted here.
    return 0 if diff.max() < 1e-6 else 1


if __name__ == "__main__":
    raise SystemExit(main())
