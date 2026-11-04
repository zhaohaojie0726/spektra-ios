"""Export deterministic golden data from the Python reference (spektrafilm).

Usage (Windows):
    set PYTHONPATH=..\\spektrafilm\\src
    ..\\spektrafilm\\.venv\\Scripts\\python.exe export_goldens.py

Writes into ./goldens:
    manifest.json        array table + params snapshot
    arrays.bin           little-endian float32, concatenated
    params.json          the exact parameter set (for the Swift side)

The pipeline runs in `debug.lut_mode = True`: spatial effects, stochastic
effects, auto-exposure and scanner corrections are off, so the result is a
deterministic per-pixel transform.  Every stage is captured through the named
taps the runtime already exposes.
"""

from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np
import colour

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO / "spektrafilm" / "src"))

from spektrafilm import init_params, digest_params  # noqa: E402
from spektrafilm.runtime.pipeline import SimulationPipeline  # noqa: E402


def synthetic_image(h: int = 24, w: int = 32) -> np.ndarray:
    """A deterministic patch grid in linear light, 0..1."""
    rng = np.random.default_rng(7)
    patches = rng.uniform(0.0, 1.0, size=(6, 8, 3))
    # a couple of anchors: black, mid-grey, white
    patches[0, 0] = (0.0, 0.0, 0.0)
    patches[0, 1] = (0.18, 0.18, 0.18)
    patches[0, 2] = (1.0, 1.0, 1.0)
    img = np.repeat(np.repeat(patches, h // 6, axis=0), w // 8, axis=1)
    return img[:h, :w].astype(np.float32)


def build_params():
    p = init_params(film_profile="kodak_portra_400",
                    print_profile="kodak_portra_endura")
    p.debug.lut_mode = True
    p.camera.auto_exposure = False
    p.camera.exposure_compensation_ev = 0.0
    p.io.input_color_space = "ProPhoto RGB"
    p.io.input_cctf_decoding = False
    p.io.output_color_space = "sRGB"
    p.io.output_cctf_encoding = True
    # CAM16-UCS output roll-off is deferred in the Swift port: the first
    # milestone targets a straight spectral scan with plain clipping.
    p.io.output_gamut_compress = replace(p.io.output_gamut_compress, algorithm="off")
    return digest_params(p)


def main() -> int:
    out = HERE / "goldens"
    out.mkdir(exist_ok=True)

    params = build_params()
    image = synthetic_image()
    pipe = SimulationPipeline(params)

    taps = ["rgb_pre", "log_e_film", "cmy_film", "log_e_print", "cmy_print", "rgb_out"]
    arrays: dict[str, np.ndarray] = {"input.rgb": image.astype(np.float64)}
    for tap in taps:
        arrays[f"taps.{tap}"] = np.asarray(
            pipe.process(image, inject="rgb_in", collect=tap), dtype=np.float64)
        print(f"{tap:14s} {arrays[f'taps.{tap}'].shape}  "
              f"mean={arrays[f'taps.{tap}'].mean():.6f}")

    # The goldens are only useful if the reference is deterministic. Glare is
    # unseeded by default and grain uses a fixed seed; `lut_mode` should turn
    # both off. If this fires, every downstream comparison is meaningless.
    repeat = np.asarray(pipe.process(image), dtype=np.float64)
    if not np.array_equal(repeat, arrays["taps.rgb_out"]):
        raise SystemExit(
            "reference pipeline is not deterministic — check "
            "debug.deactivate_stochastic_effects and print_render.glare")

    # setup constants, so the Swift side can be tested module by module
    film = params.film
    paper = params.print
    lut_service = pipe._lut_service
    sensitivity = 10 ** np.nan_to_num(film.data.log_sensitivity)
    tc_lut = lut_service.get_filming_tc_lut(sensitivity)

    # The linear map the runtime uses inside `_rgb_to_tc_b`: the input space's
    # RGB→XYZ matrix, chromatically adapted (CAT16) to the film's reference
    # illuminant. Applying it to the identity yields the 3×3 we hand to Swift.
    #
    # NOTE: the adaptation white is `_illuminant_to_xy()` — the illuminant SPD
    # integrated against the CIE 1931 CMFs — NOT colour's tabulated D55 xy.
    # They differ in the 5th decimal, which moves the tc coordinates by ~3e-6
    # and the render by ~5e-5.  Using the tabulated value silently breaks parity.
    from spektrafilm.utils.spectral_upsampling import _illuminant_to_xy

    illuminant_xy = _illuminant_to_xy(film.info.reference_illuminant)
    input_matrix = np.asarray(colour.RGB_to_XYZ(
        np.eye(3),
        colourspace=params.io.input_color_space,
        apply_cctf_decoding=False,
        illuminant=illuminant_xy,
        chromatic_adaptation_transform="CAT16",
    ))

    from spektrafilm.model.couplers import compute_dir_couplers_matrix

    couplers_matrix = compute_dir_couplers_matrix(params.film_render.dir_couplers)
    couplers_matrix = couplers_matrix * params.film_render.dir_couplers.amount

    # The enlarger chain: source spectrum × dichroic filter pack. `filtered` is
    # what the golden was rendered with; the three inputs let the Swift side
    # rebuild it when a filter slider moves.
    from spektrafilm.model.color_filters import custom_dichroic_filters
    from spektrafilm.model.illuminants import standard_illuminant

    base_illuminant = standard_illuminant(params.enlarger.illuminant)
    filtered_illuminant = pipe._enlarger_service.enlarger_filtered_illuminant(base_illuminant)
    density_spectral_midgray = np.asarray(
        pipe._enlarger_service.density_spectral_midgray).reshape(81)

    # The scanner: viewing illuminant + CIE 1931 CMFs, and the output transform
    # (XYZ → sRGB, adapted from the viewing illuminant to D65).
    from spektrafilm.config import STANDARD_OBSERVER_CMFS

    scan_illuminant = np.asarray(standard_illuminant(paper.info.viewing_illuminant)).ravel()
    cmfs = np.asarray(STANDARD_OBSERVER_CMFS[:])
    scan_normalization = float(np.sum(scan_illuminant * cmfs[:, 1]))
    scan_white_xyz = (scan_illuminant[:, None] * cmfs).sum(axis=0) / scan_normalization
    scan_white_xy = colour.XYZ_to_xy(scan_white_xyz)
    xyz_to_rgb = np.asarray(colour.XYZ_to_RGB(
        np.eye(3),
        colourspace=params.io.output_color_space,
        apply_cctf_encoding=False,
        illuminant=scan_white_xy,
    ))
    roundtrip = np.asarray(colour.RGB_to_RGB(
        np.eye(3), params.io.output_color_space, params.io.output_color_space,
        apply_cctf_decoding=False, apply_cctf_encoding=False,
    ))

    setup = {
        "setup.couplers_matrix": couplers_matrix,
        "setup.colour_matrix_srgb_to_xyz": np.asarray(colour.RGB_to_XYZ(
            np.eye(3),
            colourspace="sRGB",
            apply_cctf_decoding=False,
            illuminant=illuminant_xy,
            chromatic_adaptation_transform="CAT16",
        )),
        "setup.scan.illuminant": scan_illuminant,
        "setup.scan.cmfs": cmfs,
        "setup.scan.normalization": np.array([scan_normalization]),
        "setup.scan.xyz_to_rgb": xyz_to_rgb,
        "setup.scan.roundtrip_matrix": roundtrip,
        "setup.enlarger.base_illuminant": np.asarray(base_illuminant),
        "setup.enlarger.filtered_illuminant": np.asarray(filtered_illuminant),
        "setup.enlarger.dichroic_filters": np.asarray(custom_dichroic_filters.filters),
        "setup.enlarger.density_spectral_midgray": density_spectral_midgray,
        "setup.enlarger.cc_neutral": np.array([
            params.enlarger.c_filter_neutral,
            params.enlarger.m_filter_neutral,
            params.enlarger.y_filter_neutral,
        ]),
        "setup.film.log_sensitivity": film.data.log_sensitivity,
        "setup.film.channel_density": film.data.channel_density,
        "setup.film.base_density": film.data.base_density,
        "setup.film.log_exposure": film.data.log_exposure,
        "setup.film.density_curves": film.data.density_curves,
        "setup.print.log_sensitivity": paper.data.log_sensitivity,
        "setup.print.channel_density": paper.data.channel_density,
        "setup.print.base_density": paper.data.base_density,
        "setup.print.log_exposure": paper.data.log_exposure,
        "setup.print.density_curves": paper.data.density_curves,
        "setup.tc_lut": tc_lut,
        "setup.wavelengths": film.data.wavelengths,
        "setup.colour_matrix_input_to_xyz": input_matrix,
    }
    for k, v in setup.items():
        arrays[k] = np.asarray(v, dtype=np.float64)

    # one flat little-endian float32 blob + an index (offsets counted in floats)
    index = {}
    offset = 0
    with open(out / "arrays.bin", "wb") as fh:
        for name, arr in arrays.items():
            a = np.ascontiguousarray(arr, dtype="<f4")
            fh.write(a.tobytes())
            index[name] = {"shape": list(a.shape), "offset": offset // 4}
            offset += a.nbytes

    manifest = {
        "reference_commit": "3bb2c2d",
        "film": "kodak_portra_400",
        "print": "kodak_portra_endura",
        "lut_mode": True,
        "input_color_space": params.io.input_color_space,
        "output_color_space": params.io.output_color_space,
        "arrays": index,
        "total_floats": offset // 4,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nwrote {offset/1e6:.2f} MB, {len(index)} arrays -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
