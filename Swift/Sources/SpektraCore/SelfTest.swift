import Dispatch
import Foundation

/// Runs the golden comparisons on the device.
///
/// The same five checks the remote harness and `swift test` perform, exposed so
/// the app can prove — on the phone, with the phone's compiler and CPU — that
/// the port still produces the reference numbers. A green list here is the
/// evidence that "it runs on iOS" means more than "it drew something".
public enum SelfTest {
    public struct Result: Sendable {
        public let name: String
        public let maxDiff: Float
        public let tolerance: Float
        public var passed: Bool { maxDiff <= tolerance }
    }

    public static let tolerance: Float = 2e-5

    /// One timed render, for answering "is the CPU version fast enough".
    public struct Benchmark: Sendable {
        public let milliseconds: Double
        public let megapixels: Double
        public var millisecondsPerMegapixel: Double {
            megapixels > 0 ? milliseconds / megapixels : 0
        }
    }

    /// Renders a synthetic frame a couple of times and reports the wall clock.
    /// The first render is a warm-up and is not counted.
    public static func benchmark(width: Int = 512, height: Int = 512,
                                 iterations: Int = 2) -> Benchmark? {
        guard let pack = try? BundledPack.load() else { return nil }
        var input = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<input.count {
            input[i] = Float(i % 97) / 96
        }
        _ = pack.simulator.render(linearRGB: input, width: width, height: height)

        let runs = max(1, iterations)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<runs {
            _ = pack.simulator.render(linearRGB: input, width: width, height: height)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        return Benchmark(milliseconds: elapsed,
                         megapixels: Double(width * height * runs) / 1e6)
    }

    public static func run() -> [Result] {
        do {
            return try evaluate()
        } catch {
            return [Result(name: "self-test could not run: \(error)", maxDiff: .infinity, tolerance: tolerance)]
        }
    }

    private static func evaluate() throws -> [Result] {
        let golden = try Golden.bundled()
        let film = try Profile.load(named: "kodak_portra_400")
        let paper = try Profile.load(named: "kodak_portra_endura")

        func array(_ name: String) throws -> (shape: [Int], values: [Float]) {
            guard let value = golden.array(name) else {
                throw BundledPack.LoadError.missing(name)
            }
            return value
        }

        let input = try array("input.rgb")
        let width = input.shape[1]
        let height = input.shape[0]

        let expectedLog = try array("taps.log_e_film")
        let expectedNegative = try array("taps.cmy_film")
        let expectedPrint = try array("taps.log_e_print")
        let expectedDensity = try array("taps.cmy_print")
        let expectedRGB = try array("taps.rgb_out")

        let matrix = ColourMatrix(rowMajor: try array("setup.colour_matrix_input_to_xyz").values)
        let lutShape = try array("setup.tc_lut").shape
        let table = ChromaTable(size: lutShape[0], channels: lutShape[2],
                                values: try array("setup.tc_lut").values)
        let couplers = Matrix3(rowMajor: try array("setup.couplers_matrix").values)

        var results: [Result] = []

        let logFilm = FilmExposure.logExposure(rgb: input.values, width: width, height: height,
                                               matrix: matrix, table: table)
        results.append(Result(name: "stage 1  RGB -> film log exposure",
                              maxDiff: maxDiff(logFilm, expectedLog.values),
                              tolerance: tolerance))

        let curves = CharacteristicCurves(logExposure: film.logExposure,
                                          densityCurves: film.densityCurves)
        let negative = FilmDevelopment.density(logExposure: logFilm, width: width, height: height,
                                               curves: curves, couplers: couplers)
        results.append(Result(name: "stage 2  -> negative density",
                              maxDiff: maxDiff(negative, expectedNegative.values),
                              tolerance: tolerance))

        let cc = try array("setup.enlarger.cc_neutral").values
        let enlarger = EnlargerSetup(baseIlluminant: try array("setup.enlarger.base_illuminant").values,
                                     dichroicFilters: try array("setup.enlarger.dichroic_filters").values,
                                     ccNeutral: SIMD3(cc[0], cc[1], cc[2]))
        let filtered = enlarger.filteredIlluminant(cc: enlarger.ccNeutral)
        results.append(Result(name: "enlarger dichroic model",
                              maxDiff: maxDiff(filtered,
                                               try array("setup.enlarger.filtered_illuminant").values),
                              tolerance: tolerance))

        let sensitivity = PrintingExposure.linearSensitivity(try array("setup.print.log_sensitivity").values)
        let midgray = try array("setup.enlarger.density_spectral_midgray").values
        let factor = PrintingExposure.midgrayFactor(midgrayDensity: midgray,
                                                    filteredIlluminant: filtered,
                                                    paperSensitivity: sensitivity)
        let logPrint = PrintingExposure.logExposure(cmy: negative, width: width, height: height,
                                                    filmChannelDensity: film.channelDensity,
                                                    filmBaseDensity: film.baseDensity,
                                                    paperSensitivity: sensitivity,
                                                    filteredIlluminant: filtered,
                                                    midgrayFactor: factor)
        results.append(Result(name: "stage 3  -> paper exposure",
                              maxDiff: maxDiff(logPrint, expectedPrint.values),
                              tolerance: tolerance))

        guard let model = paper.densityModel else {
            throw BundledPack.LoadError.missing("paper density model")
        }
        let printDensity = PrintDevelopment.density(logExposure: logPrint, width: width, height: height,
                                                    exposureAxis: paper.logExposure,
                                                    model: model,
                                                    positive: paper.info.type == "positive")
        results.append(Result(name: "stage 4  -> print density",
                              maxDiff: maxDiff(printDensity, expectedDensity.values),
                              tolerance: tolerance))

        let rgb = Scanning.outputRGB(cmy: printDensity, width: width, height: height,
                                     channelDensity: paper.channelDensity,
                                     baseDensity: paper.baseDensity,
                                     viewingIlluminant: try array("setup.scan.illuminant").values,
                                     cmfs: try array("setup.scan.cmfs").values,
                                     normalization: try array("setup.scan.normalization").values[0],
                                     xyzToRGB: ColourMatrix(rowMajor: try array("setup.scan.xyz_to_rgb").values),
                                     roundtrip: ColourMatrix(rowMajor: try array("setup.scan.roundtrip_matrix").values),
                                     encode: true)
        results.append(Result(name: "stage 5  -> output RGB",
                              maxDiff: maxDiff(rgb, expectedRGB.values),
                              tolerance: tolerance))

        // Every shipped pack must load and produce a sane 18 % grey. This is the
        // part of the data path the stage checks above do not touch.
        for identifier in BundledPack.availableIDs() {
            var worst: Float = 0
            do {
                let pack = try BundledPack.load(id: identifier)
                let grey = [Float](repeating: 0.18, count: 4 * 4 * 3)
                let out = pack.simulator.render(linearRGB: grey, width: 4, height: 4)
                for value in out where !value.isFinite || value < -0.05 || value > 1.05 {
                    worst = .infinity
                }
            } catch {
                worst = .infinity
            }
            results.append(Result(name: "pack  \(identifier)",
                                  maxDiff: worst,
                                  tolerance: tolerance))
        }

        return results
    }

    private static func maxDiff(_ a: [Float], _ b: [Float]) -> Float {
        var worst: Float = 0
        for i in 0..<min(a.count, b.count) {
            worst = max(worst, abs(a[i] - b[i]))
        }
        return worst
    }
}
