"""Run the Swift core on a real compiler and compare against the golden data.

    python Tools/run-remote-tests.py [compiler-id]

The core sources plus a generated driver are compiled and **executed** on
Compiler Explorer (Linux x86-64). The golden arrays are embedded as base64, so
no file system or bundle is involved.

Covers all five stages, the enlarger's dichroic model and the sRGB transfer
function. `ImageBridge` (Core Graphics) and the SwiftUI layer cannot run here.
"""

from __future__ import annotations

import base64
import json
import pathlib
import struct
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Swift" / "Sources" / "SpektraCore"
RESOURCES = SOURCES / "Resources" / "goldens"

ORDER = [
    "MathCompat", "SRGB", "Parallel", "Colour", "ChromaTable", "Curves", "DensityModel", "Profile",
    "Golden", "BundledPack", "FilmExposure", "FilmDevelopment", "Printing",
    "Scanning", "PrintDevelopment", "Simulation", "SelfTest",
]


def srgb_decode(x: float) -> float:
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


def srgb_encode(x: float) -> float:
    return 12.92 * x if x <= 0.0031308 else 1.055 * (x ** (1 / 2.4)) - 0.055

STUB = """
extension Bundle { static var module: Bundle { Bundle.main } }
"""


def load_arrays() -> dict[str, list[float]]:
    manifest = json.loads((RESOURCES / "manifest.json").read_text(encoding="utf-8"))
    blob = (RESOURCES / "arrays.bin").read_bytes()
    arrays = {}
    for name, entry in manifest["arrays"].items():
        count = 1
        for dimension in entry["shape"]:
            count *= dimension
        start = entry["offset"] * 4
        values = struct.unpack_from(f"<{count}f", blob, start)
        arrays[name] = list(values)
    return arrays


def paper_model() -> dict[str, list[float]]:
    profile = ROOT / "spektrafilm" / "src" / "spektrafilm" / "data" / "profiles" / "kodak_portra_endura.json"
    model = json.loads(profile.read_text(encoding="utf-8"))["data"]["density_curves_model"]
    out = {}
    for key in ("centers", "amplitudes", "sigmas"):
        flat = [value for channel in model[key] for value in channel]
        out[key] = flat
    return out


def literal(name: str, values: list[float]) -> str:
    raw = struct.pack(f"<{len(values)}f", *values)
    encoded = base64.b64encode(raw).decode("ascii")
    chunks = [encoded[i:i + 900] for i in range(0, len(encoded), 900)]
    body = ",\n        ".join(f'"{chunk}"' for chunk in chunks)
    # An array literal joined at run time: a chain of `+` on hundreds of
    # literals makes the Swift type checker's head explode.
    return f'let {name} = Self.decode(\n        [{body}].joined())\n'


def driver(arrays: dict[str, list[float]], model: dict[str, list[float]]) -> str:
    selected = {
        "inputRgb": "input.rgb",
        "tcLut": "setup.tc_lut",
        "inputMatrix": "setup.colour_matrix_input_to_xyz",
        "logEFilm": "taps.log_e_film",
        "cmyFilm": "taps.cmy_film",
        "logEPrint": "taps.log_e_print",
        "cmyPrint": "taps.cmy_print",
        "rgbOut": "taps.rgb_out",
        "filmExposure": "setup.film.log_exposure",
        "filmCurves": "setup.film.density_curves",
        "filmLogSensitivity": "setup.film.log_sensitivity",
        "couplers": "setup.couplers_matrix",
        "filmChannelDensity": "setup.film.channel_density",
        "filmBaseDensity": "setup.film.base_density",
        "paperLogSensitivity": "setup.print.log_sensitivity",
        "paperChannelDensity": "setup.print.channel_density",
        "paperBaseDensity": "setup.print.base_density",
        "paperExposure": "setup.print.log_exposure",
        "filtered": "setup.enlarger.filtered_illuminant",
        "midgray": "setup.enlarger.density_spectral_midgray",
        "scanIlluminant": "setup.scan.illuminant",
        "cmfs": "setup.scan.cmfs",
        "normalization": "setup.scan.normalization",
        "xyzToRGB": "setup.scan.xyz_to_rgb",
        "roundtrip": "setup.scan.roundtrip_matrix",
        "baseIlluminant": "setup.enlarger.base_illuminant",
        "dichroic": "setup.enlarger.dichroic_filters",
        "ccNeutral": "setup.enlarger.cc_neutral",
    }

    parts = ["\n// ===== driver =====\n", "@main\nstruct Runner {\n"]
    parts.append("""
    static func decode(_ chunks: String) -> [Float] {
        guard let data = Data(base64Encoded: chunks) else { return [] }
        var out = [Float](repeating: 0, count: data.count / 4)
        data.withUnsafeBytes { raw in
            for i in 0..<out.count {
                out[i] = raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self)
            }
        }
        return out
    }

    static func maxDiff(_ a: [Float], _ b: [Float]) -> Float {
        var m: Float = 0
        for i in 0..<min(a.count, b.count) { m = max(m, abs(a[i] - b[i])) }
        return m
    }

    static func worst(_ a: [Float], _ b: [Float]) -> (Float, Int) {
        var m: Float = 0
        var index = 0
        for i in 0..<min(a.count, b.count) {
            let d = abs(a[i] - b[i])
            if d > m { m = d; index = i }
        }
        return (m, index)
    }

    static func main() {
""")
    for swift_name, golden_name in selected.items():
        parts.append(literal(swift_name, arrays[golden_name]))
    for key, swift_name in (("centers", "modelCenters"),
                            ("amplitudes", "modelAmplitudes"),
                            ("sigmas", "modelSigmas")):
        parts.append(literal(swift_name, model[key]))
    parts.append(literal("srgbDecodeExpected", [srgb_decode(i / 1000) for i in range(1001)]))
    parts.append(literal("srgbEncodeExpected", [srgb_encode(i / 1000) for i in range(1001)]))

    parts.append("""
        let width = 32, height = 24

        let lutSize = Int((Double(tcLut.count) / 3).squareRoot())
        let logFilm = FilmExposure.logExposure(rgb: inputRgb, width: width, height: height,
                                               matrix: ColourMatrix(rowMajor: inputMatrix),
                                               table: ChromaTable(size: lutSize, channels: 3, values: tcLut))
        print("stage1", worst(logFilm, logEFilm).0)

        let curves = CharacteristicCurves(logExposure: filmExposure, densityCurves: filmCurves)
        let density = FilmDevelopment.density(logExposure: logFilm, width: width, height: height,
                                              curves: curves, couplers: Matrix3(rowMajor: couplers))
        print("stage2", worst(density, cmyFilm).0)

        let sensitivity = PrintingExposure.linearSensitivity(paperLogSensitivity)
        let factor = PrintingExposure.midgrayFactor(midgrayDensity: midgray,
                                                    filteredIlluminant: filtered,
                                                    paperSensitivity: sensitivity)
        let printExposure = PrintingExposure.logExposure(cmy: density, width: width, height: height,
                                                         filmChannelDensity: filmChannelDensity,
                                                         filmBaseDensity: filmBaseDensity,
                                                         paperSensitivity: sensitivity,
                                                         filteredIlluminant: filtered,
                                                         midgrayFactor: factor)
        print("stage3", maxDiff(printExposure, logEPrint))

        let model = DensityCurveModel(modelType: "cdfs",
                                      centers: [[modelCenters[0], modelCenters[1], modelCenters[2]],
                                                [modelCenters[3], modelCenters[4], modelCenters[5]],
                                                [modelCenters[6], modelCenters[7], modelCenters[8]]],
                                      amplitudes: [[modelAmplitudes[0], modelAmplitudes[1], modelAmplitudes[2]],
                                                   [modelAmplitudes[3], modelAmplitudes[4], modelAmplitudes[5]],
                                                   [modelAmplitudes[6], modelAmplitudes[7], modelAmplitudes[8]]],
                                      sigmas: [[modelSigmas[0], modelSigmas[1], modelSigmas[2]],
                                               [modelSigmas[3], modelSigmas[4], modelSigmas[5]],
                                               [modelSigmas[6], modelSigmas[7], modelSigmas[8]]])
        let printDensity = PrintDevelopment.density(logExposure: printExposure, width: width, height: height,
                                                    exposureAxis: paperExposure, model: model, positive: false)
        print("stage4", maxDiff(printDensity, cmyPrint))

        let rgb = Scanning.outputRGB(cmy: printDensity, width: width, height: height,
                                     channelDensity: paperChannelDensity,
                                     baseDensity: paperBaseDensity,
                                     viewingIlluminant: scanIlluminant,
                                     cmfs: cmfs,
                                     normalization: normalization[0],
                                     xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                     roundtrip: ColourMatrix(rowMajor: roundtrip),
                                     encode: true)
        print("stage5", maxDiff(rgb, rgbOut))

        // Row-parallel printing and scanning must be bit-identical to serial.
        let serialPrint = PrintingExposure.logExposure(cmy: density, width: width, height: height,
                                                       filmChannelDensity: filmChannelDensity,
                                                       filmBaseDensity: filmBaseDensity,
                                                       paperSensitivity: sensitivity,
                                                       filteredIlluminant: filtered,
                                                       midgrayFactor: factor, threads: 1)
        let parallelPrint = PrintingExposure.logExposure(cmy: density, width: width, height: height,
                                                         filmChannelDensity: filmChannelDensity,
                                                         filmBaseDensity: filmBaseDensity,
                                                         paperSensitivity: sensitivity,
                                                         filteredIlluminant: filtered,
                                                         midgrayFactor: factor, threads: 4)
        print("threads-print", maxDiff(serialPrint, parallelPrint))

        let serialScan = Scanning.outputRGB(cmy: printDensity, width: width, height: height,
                                            channelDensity: paperChannelDensity,
                                            baseDensity: paperBaseDensity,
                                            viewingIlluminant: scanIlluminant, cmfs: cmfs,
                                            normalization: normalization[0],
                                            xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                            roundtrip: ColourMatrix(rowMajor: roundtrip),
                                            encode: true, threads: 1)
        let parallelScan = Scanning.outputRGB(cmy: printDensity, width: width, height: height,
                                              channelDensity: paperChannelDensity,
                                              baseDensity: paperBaseDensity,
                                              viewingIlluminant: scanIlluminant, cmfs: cmfs,
                                              normalization: normalization[0],
                                              xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                              roundtrip: ColourMatrix(rowMajor: roundtrip),
                                              encode: true, threads: 4)
        print("threads-scan", maxDiff(serialScan, parallelScan))

        // The enlarger's dichroic model: the only piece of `Simulator` that is
        // not already covered by stages 1-5 (which used the precomputed
        // filtered spectrum).
        let enlarger = EnlargerSetup(baseIlluminant: baseIlluminant,
                                     dichroicFilters: dichroic,
                                     ccNeutral: SIMD3(ccNeutral[0], ccNeutral[1], ccNeutral[2]))
        let rebuilt = enlarger.filteredIlluminant(cc: enlarger.ccNeutral)
        print("filter", worst(rebuilt, filtered).0)

        var srgbWorst: Float = 0
        for i in 0...1000 {
            let v = Float(i) / 1000
            srgbWorst = max(srgbWorst, abs(SRGB.decode(v) - srgbDecodeExpected[i]))
            srgbWorst = max(srgbWorst, abs(SRGB.encode(v) - srgbEncodeExpected[i]))
        }
        print("srgb", srgbWorst)

        // The composition the app actually calls: `Simulator.render`.
        let wavelengths = (0..<81).map { 380 + Float($0) * 5 }
        let filmProfile = Profile(
            info: Profile.Info(stock: "kodak_portra_400", name: "film", type: "negative",
                               support: "film", channelModel: "color",
                               referenceIlluminant: "D55", viewingIlluminant: "D50"),
            wavelengths: wavelengths,
            logSensitivity: filmLogSensitivity,
            channelDensity: filmChannelDensity,
            baseDensity: filmBaseDensity,
            logExposure: filmExposure,
            densityCurves: filmCurves,
            densityModel: nil)
        let paperProfile = Profile(
            info: Profile.Info(stock: "kodak_portra_endura", name: "paper", type: "negative",
                               support: "paper", channelModel: "color",
                               referenceIlluminant: "D55", viewingIlluminant: "D50"),
            wavelengths: wavelengths,
            logSensitivity: paperLogSensitivity,
            channelDensity: paperChannelDensity,
            baseDensity: paperBaseDensity,
            logExposure: paperExposure,
            densityCurves: [],
            densityModel: model)

        let simulator = Simulator(film: filmProfile, paper: paperProfile,
                                  inputMatrix: ColourMatrix(rowMajor: inputMatrix),
                                  chromaTable: ChromaTable(size: lutSize, channels: 3, values: tcLut),
                                  couplers: Matrix3(rowMajor: couplers),
                                  enlarger: enlarger,
                                  scan: Scanning.Setup(viewingIlluminant: scanIlluminant,
                                                       cmfs: cmfs,
                                                       normalization: normalization[0],
                                                       xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                                       roundtrip: ColourMatrix(rowMajor: roundtrip),
                                                       encode: true),
                                  midgrayDensity: midgray)
        let endToEnd = simulator.render(linearRGB: inputRgb, width: width, height: height)
        print("simulator", worst(endToEnd, rgbOut).0)

        // A rough speed check: the same frame serial and across all cores.
        var big = [Float](repeating: 0, count: 192 * 192 * 3)
        for i in 0..<big.count { big[i] = Float(i % 101) / 100 }
        var serialSimulator = simulator
        serialSimulator.threads = 1
        _ = serialSimulator.render(linearRGB: big, width: 192, height: 192)

        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = serialSimulator.render(linearRGB: big, width: 192, height: 192)
        let serialMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6

        _ = simulator.render(linearRGB: big, width: 192, height: 192)
        let t1 = DispatchTime.now().uptimeNanoseconds
        _ = simulator.render(linearRGB: big, width: 192, height: 192)
        let parallelMs = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1e6
        print("bench", String(format: "serial %.0f ms, parallel %.0f ms (cores %d)",
                              serialMs, parallelMs, ProcessInfo.processInfo.activeProcessorCount))

        // Calibration: how fast is this machine at all? ~50M fused multiply-adds.
        var accumulator: Float = 0
        let c0 = DispatchTime.now().uptimeNanoseconds
        for i in 0..<50_000_000 {
            accumulator += Float(i & 1023) * 1.000001
        }
        let calibrationMs = Double(DispatchTime.now().uptimeNanoseconds - c0) / 1e6
        print("calibration", String(format: "%.0f ms for 50M fma (%.2f GFLOP/s), sink %f",
                                    calibrationMs, 0.2 / (calibrationMs / 1000), accumulator))

        // Strips must be bit-identical to the whole-frame render.
        let stripped = simulator.render(linearRGB: inputRgb, width: width, height: height, stripHeight: 5)
        print("strips", maxDiff(endToEnd, stripped))
    }
}
""")
    return "".join(parts)


def merged(arrays, model) -> str:
    parts = ["import Foundation\n", STUB]
    for name in ORDER:
        parts.append(f"\n// ===== {name}.swift =====\n")
        parts.append((SOURCES / f"{name}.swift").read_text(encoding="utf-8"))
    parts.append(driver(arrays, model))
    return "".join(parts)


def compile_and_run(source: str, compiler: str) -> dict:
    body = {
        "source": source,
        "options": {
            "userArguments": "-parse-as-library -swift-version 5",
            "filters": {"execute": True},
        },
    }
    request = urllib.request.Request(
        f"https://godbolt.org/api/compiler/{compiler}/compile",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    arguments = [a for a in sys.argv[1:] if not a.startswith("-")]
    compiler = arguments[0] if arguments else "swift603"
    source = merged(load_arrays(), paper_model())
    print(f"uploading {len(source)/1000:.0f} KB to {compiler}")

    result = compile_and_run(source, compiler)
    for entry in result.get("stderr") or []:
        print(entry.get("text", ""))
    execution = result.get("execResult") or {}
    for entry in execution.get("stdout") or []:
        print(entry.get("text", ""))
    for entry in execution.get("stderr") or []:
        print("exec:", entry.get("text", ""))
    print("exit", result.get("code"), "exec", execution.get("code"))
    return 0 if result.get("code") == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

