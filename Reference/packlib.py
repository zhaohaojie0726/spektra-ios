"""Bake and replay a film pack: the constants one (film, paper) pair needs,
and a renderer that uses nothing but those constants plus the two profiles.

The replay is a transliteration of the Swift `Simulator`, so a pack that
replays correctly in Python will replay correctly in Swift.
"""

from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "spektrafilm" / "src"))

import colour  # noqa: E402

from spektrafilm import init_params, digest_params  # noqa: E402
from spektrafilm.config import STANDARD_OBSERVER_CMFS  # noqa: E402
from spektrafilm.model.color_filters import custom_dichroic_filters  # noqa: E402
from spektrafilm.model.couplers import compute_dir_couplers_matrix  # noqa: E402
from spektrafilm.model.illuminants import standard_illuminant  # noqa: E402
from spektrafilm.runtime.pipeline import SimulationPipeline  # noqa: E402
from spektrafilm.utils.spectral_upsampling import _illuminant_to_xy  # noqa: E402


def build(film: str, paper: str,
          input_space: str = "ProPhoto RGB",
          output_space: str = "sRGB") -> tuple[dict, dict, object, object]:
    """Runs the reference setup and returns the pack arrays plus its context."""
    params = init_params(film_profile=film, print_profile=paper)
    params.debug.lut_mode = True
    params.camera.auto_exposure = False
    params.io.input_color_space = input_space
    params.io.output_color_space = output_space
    params.io.output_gamut_compress = replace(params.io.output_gamut_compress,
                                              algorithm="off")
    params = digest_params(params)
    pipeline = SimulationPipeline(params)

    film_profile = params.film
    paper_profile = params.print

    sensitivity = 10 ** np.nan_to_num(film_profile.data.log_sensitivity)
    tc_lut = pipeline._lut_service.get_filming_tc_lut(sensitivity)

    illuminant_xy = _illuminant_to_xy(film_profile.info.reference_illuminant)

    def matrix(space: str) -> np.ndarray:
        return np.asarray(colour.RGB_to_XYZ(
            np.eye(3), colourspace=space, apply_cctf_decoding=False,
            illuminant=illuminant_xy, chromatic_adaptation_transform="CAT16"))

    base_illuminant = standard_illuminant(params.enlarger.illuminant)
    filtered = pipeline._enlarger_service.enlarger_filtered_illuminant(base_illuminant)
    midgray = np.asarray(pipeline._enlarger_service.density_spectral_midgray).reshape(81)

    cmfs = np.asarray(STANDARD_OBSERVER_CMFS[:])
    scan_illuminant = np.asarray(standard_illuminant(paper_profile.info.viewing_illuminant)).ravel()
    normalization = float(np.sum(scan_illuminant * cmfs[:, 1]))
    white_xyz = (scan_illuminant[:, None] * cmfs).sum(axis=0) / normalization
    white_xy = colour.XYZ_to_xy(white_xyz)

    arrays = {
        "input_matrix": matrix(input_space),
        "input_matrix_srgb": matrix("sRGB"),
        "tc_lut": tc_lut,
        "couplers_matrix": compute_dir_couplers_matrix(params.film_render.dir_couplers)
        * params.film_render.dir_couplers.amount,
        "enlarger.base_illuminant": np.asarray(base_illuminant),
        "enlarger.filtered_illuminant": np.asarray(filtered),
        "enlarger.dichroic_filters": np.asarray(custom_dichroic_filters.filters),
        "enlarger.cc_neutral": np.array([
            params.enlarger.c_filter_neutral,
            params.enlarger.m_filter_neutral,
            params.enlarger.y_filter_neutral,
        ]),
        "enlarger.midgray_density": midgray,
        "scan.illuminant": scan_illuminant,
        "scan.cmfs": cmfs,
        "scan.normalization": np.array([normalization]),
        "scan.xyz_to_rgb": np.asarray(colour.XYZ_to_RGB(
            np.eye(3), colourspace=output_space, apply_cctf_encoding=False,
            illuminant=white_xy)),
        "scan.roundtrip_matrix": np.asarray(colour.RGB_to_RGB(
            np.eye(3), output_space, output_space,
            apply_cctf_decoding=False, apply_cctf_encoding=False)),
    }
    meta = {
        "film": film,
        "paper": paper,
        "input_color_space": input_space,
        "output_color_space": output_space,
        "reference_commit": "3bb2c2d",
        "format_version": 1,
    }
    return arrays, meta, params, pipeline


def _fast_interp(image: np.ndarray, axis: np.ndarray, values: np.ndarray) -> np.ndarray:
    k = axis.shape[0]
    out = np.empty_like(image)
    for channel in range(3):
        xp = axis[:, channel]
        column = image[:, :, channel]
        for index in np.ndindex(column.shape):
            x = column[index]
            if x <= xp[0]:
                out[index][channel] = values[0, channel]
            elif x >= xp[k - 1]:
                out[index][channel] = values[k - 1, channel]
            else:
                j = int(np.searchsorted(xp, x, side="right"))
                i = max(j - 1, 0)
                dx = xp[j] - xp[i]
                t = (x - xp[i]) / dx if dx != 0 else 0.0
                out[index][channel] = values[i, channel] + t * (values[j, channel] - values[i, channel])
    return out


def _srgb_encode(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.0031308, 12.92 * x,
                    1.055 * np.power(np.maximum(x, 0.0), 1 / 2.4) - 0.055)


def render(arrays: dict, params, image: np.ndarray) -> np.ndarray:
    """The Swift `Simulator.render`, in numpy."""
    film = params.film
    paper = params.print
    height, width, _ = image.shape

    # 1. film exposure
    rgb = image.astype(np.float64)
    xyz = rgb @ arrays["input_matrix"]
    b = xyz.sum(axis=-1)
    denominator = np.maximum(b, 1e-10)
    xy = xyz[..., :2] / denominator[..., None]
    s = 1 - xy[..., 0]
    tx = np.clip(s * s, 0, 1)
    ty = np.clip(xy[..., 1] / np.maximum(s, 1e-10), 0, 1)
    lut = arrays["tc_lut"]
    n = lut.shape[0]
    raw = np.zeros_like(rgb)
    for i, j in np.ndindex(height, width):
        raw[i, j] = _cubic_lookup(lut, tx[i, j] * (n - 1), ty[i, j] * (n - 1)) * b[i, j]
    log_e = np.log10(np.maximum(raw, 0) + 1e-10)

    # 2. film development
    curves = film.data.density_curves
    curves = curves - np.nanmin(curves, axis=0)
    axis = np.repeat(film.data.log_exposure[:, None], 3, axis=1)
    couplers = arrays["couplers_matrix"]
    density = _fast_interp(log_e, axis, curves)
    amount = curves @ couplers
    shifted = film.data.log_exposure[:, None] - amount
    base_curves = np.zeros_like(curves)
    for channel in range(3):
        base_curves[:, channel] = np.interp(film.data.log_exposure, shifted[:, channel],
                                            curves[:, channel])
    log_e0 = log_e - density @ couplers
    negative = _fast_interp(log_e0, axis, base_curves)

    # 3. print exposure
    # The spectral density here is the NEGATIVE's (the film's dyes); the
    # sensitivity is the paper's. Using the paper's dye curves would model a
    # print developed from its own dyes.
    sensitivity = 10 ** np.nan_to_num(paper.data.log_sensitivity)
    spectral = negative @ film.data.channel_density.T + film.data.base_density
    light = 10.0 ** (-spectral) * arrays["enlarger.filtered_illuminant"]
    light[np.isnan(light)] = 0
    raw_print = light @ sensitivity
    mid_light = 10.0 ** (-arrays["enlarger.midgray_density"]) * arrays["enlarger.filtered_illuminant"]
    # the profile's spectral arrays carry NaN where nothing was measured; the
    # reference's `density_to_light` zeroes those samples, so must we
    mid_light = np.where(np.isnan(mid_light), 0.0, mid_light)
    raw_mid = np.fmax(mid_light @ sensitivity, 1e-10)
    factor = 1.0 / np.exp(np.mean(np.log(raw_mid), axis=0))
    log_print = np.log10(np.maximum(raw_print * factor, 0) + 1e-10)

    # 4. print development
    model = paper.data.density_curves_model
    positive = paper.info.type == "positive"
    evaluated = np.stack([
        _channel_curve(paper.data.log_exposure, model, channel, positive)
        for channel in range(3)], axis=-1)
    print_density = _fast_interp(log_print, axis, evaluated)

    # 5. scanning
    p_spectral = print_density @ paper.data.channel_density.T + paper.data.base_density
    p_light = 10.0 ** (-p_spectral) * arrays["scan.illuminant"]
    p_light[np.isnan(p_light)] = 0
    xyz_out = (p_light @ arrays["scan.cmfs"]) / float(arrays["scan.normalization"][0])
    linear = xyz_out @ arrays["scan.xyz_to_rgb"]
    linear = linear @ arrays["scan.roundtrip_matrix"]
    return _srgb_encode(linear)


def _cubic_lookup(lut: np.ndarray, x: float, y: float) -> np.ndarray:
    size = lut.shape[0]
    b, c = 1 / 3, 1 / 3

    def weight(t: float) -> float:
        t = abs(t)
        if t < 1:
            return (1 / 6) * ((12 - 9 * b - 6 * c) * t ** 3 + (-18 + 12 * b + 6 * c) * t ** 2 + (6 - 2 * b))
        if t < 2:
            return (1 / 6) * ((-b - 6 * c) * t ** 3 + (6 * b + 30 * c) * t ** 2
                              + (-12 * b - 48 * c) * t + (8 * b + 24 * c))
        return 0.0

    def base_fraction(coordinate: float) -> tuple[int, float]:
        upper = float(size - 1)
        coordinate = min(max(coordinate, 0.0), upper)
        if coordinate >= upper:
            return size - 2, 1.0
        base = int(np.floor(coordinate))
        return base, coordinate - base

    def reflect(index: int) -> int:
        if index < 0:
            return -index
        if index >= size:
            return 2 * (size - 1) - index
        return index

    bx, fx = base_fraction(x)
    by, fy = base_fraction(y)
    wx = [weight(fx + 1 - i) for i in range(4)]
    wy = [weight(fy + 1 - j) for j in range(4)]
    out = np.zeros(3)
    total = 0.0
    for i in range(4):
        for j in range(4):
            w = wx[i] * wy[j]
            total += w
            out += w * lut[reflect(bx - 1 + i), reflect(by - 1 + j)]
    return out / total if total else out


def _channel_curve(axis: np.ndarray, model, channel: int, positive: bool) -> np.ndarray:
    from scipy.special import erf

    centers = np.asarray(model.centers[channel])
    amplitudes = np.asarray(model.amplitudes[channel])
    sigmas = np.asarray(model.sigmas[channel])
    total = np.zeros_like(axis)
    for i in range(len(centers)):
        z = (axis - centers[i]) / sigmas[i]
        signed = -z if positive else z
        total += amplitudes[i] * 0.5 * (1 + erf(signed / np.sqrt(2)))
    return total


def write_pack(arrays: dict, meta: dict, directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    index = {}
    offset = 0
    with open(directory / "arrays.bin", "wb") as handle:
        for name, value in arrays.items():
            data = np.ascontiguousarray(value, dtype="<f4")
            handle.write(data.tobytes())
            index[name] = {"shape": list(data.shape), "offset": offset // 4}
            offset += data.nbytes
    (directory / "manifest.json").write_text(
        json.dumps({"arrays": index}, indent=2), encoding="utf-8")
    (directory / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


def read_pack(directory: Path) -> tuple[dict, dict]:
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    blob = np.fromfile(directory / "arrays.bin", dtype="<f4")
    arrays = {}
    for name, entry in manifest["arrays"].items():
        count = int(np.prod(entry["shape"]))
        arrays[name] = blob[entry["offset"]:entry["offset"] + count].reshape(entry["shape"]).astype(np.float64)
    meta = json.loads((directory / "meta.json").read_text(encoding="utf-8"))
    return arrays, meta
