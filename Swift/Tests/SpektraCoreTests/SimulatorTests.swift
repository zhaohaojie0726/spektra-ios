import XCTest
@testable import SpektraCore

final class SimulatorTests: XCTestCase {
    /// The whole pipeline, wired the way the app wires it.
    func testEndToEndMatchesThePythonReference() throws {
        let golden = try Golden.bundled()
        let film = try Profile.load(named: "kodak_portra_400")
        let paper = try Profile.load(named: "kodak_portra_endura")

        guard let (inputShape, input) = golden.array("input.rgb"),
              let (_, expected) = golden.array("taps.rgb_out"),
              let (_, matrix) = golden.array("setup.colour_matrix_input_to_xyz"),
              let (lutShape, lut) = golden.array("setup.tc_lut"),
              let (_, couplers) = golden.array("setup.couplers_matrix"),
              let (_, baseIlluminant) = golden.array("setup.enlarger.base_illuminant"),
              let (_, dichroic) = golden.array("setup.enlarger.dichroic_filters"),
              let (_, cc) = golden.array("setup.enlarger.cc_neutral"),
              let (_, midgray) = golden.array("setup.enlarger.density_spectral_midgray"),
              let (_, scanIlluminant) = golden.array("setup.scan.illuminant"),
              let (_, cmfs) = golden.array("setup.scan.cmfs"),
              let (_, normalization) = golden.array("setup.scan.normalization"),
              let (_, xyzToRGB) = golden.array("setup.scan.xyz_to_rgb"),
              let (_, roundtrip) = golden.array("setup.scan.roundtrip_matrix")
        else { return XCTFail("golden arrays missing") }

        let simulator = Simulator(
            film: film,
            paper: paper,
            inputMatrix: ColourMatrix(rowMajor: matrix),
            chromaTable: ChromaTable(size: lutShape[0], channels: lutShape[2], values: lut),
            couplers: Matrix3(rowMajor: couplers),
            enlarger: EnlargerSetup(baseIlluminant: baseIlluminant,
                                    dichroicFilters: dichroic,
                                    ccNeutral: SIMD3(cc[0], cc[1], cc[2])),
            scan: Scanning.Setup(viewingIlluminant: scanIlluminant,
                                 cmfs: cmfs,
                                 normalization: normalization[0],
                                 xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                 roundtrip: ColourMatrix(rowMajor: roundtrip),
                                 encode: true),
            midgrayDensity: midgray)

        let got = simulator.render(linearRGB: input,
                                   width: inputShape[1],
                                   height: inputShape[0])

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            maxDiff = max(maxDiff, d)
        }
        meanDiff /= Double(got.count)
        print("end-to-end max |diff| = \(maxDiff), mean = \(meanDiff)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    /// A filter-pack shift must move the picture, and by a visible-but-sane
    /// amount — a smoke test that the slider is wired.
    func testFilterShiftChangesThePrint() throws {
        let simulator = try makeSimulator()
        let input = [Float](repeating: 0.18, count: 4 * 4 * 3)
        var shifted = simulator
        shifted.filterShift = SIMD3(0, 10, 0)

        let a = simulator.render(linearRGB: input, width: 4, height: 4)
        let b = shifted.render(linearRGB: input, width: 4, height: 4)
        var maxDiff: Float = 0
        for i in 0..<a.count { maxDiff = max(maxDiff, abs(a[i] - b[i])) }
        XCTAssertGreaterThan(maxDiff, 1e-4)
        XCTAssertLessThan(maxDiff, 0.2)
    }

    // MARK: - helpers

    private func makeSimulator() throws -> Simulator {
        let golden = try Golden.bundled()
        let film = try Profile.load(named: "kodak_portra_400")
        let paper = try Profile.load(named: "kodak_portra_endura")
        guard let (_, matrix) = golden.array("setup.colour_matrix_input_to_xyz"),
              let (lutShape, lut) = golden.array("setup.tc_lut"),
              let (_, couplers) = golden.array("setup.couplers_matrix"),
              let (_, baseIlluminant) = golden.array("setup.enlarger.base_illuminant"),
              let (_, dichroic) = golden.array("setup.enlarger.dichroic_filters"),
              let (_, cc) = golden.array("setup.enlarger.cc_neutral"),
              let (_, midgray) = golden.array("setup.enlarger.density_spectral_midgray"),
              let (_, scanIlluminant) = golden.array("setup.scan.illuminant"),
              let (_, cmfs) = golden.array("setup.scan.cmfs"),
              let (_, normalization) = golden.array("setup.scan.normalization"),
              let (_, xyzToRGB) = golden.array("setup.scan.xyz_to_rgb"),
              let (_, roundtrip) = golden.array("setup.scan.roundtrip_matrix")
        else { throw Golden.LoadError.malformed("assembling the simulator") }

        return Simulator(
            film: film,
            paper: paper,
            inputMatrix: ColourMatrix(rowMajor: matrix),
            chromaTable: ChromaTable(size: lutShape[0], channels: lutShape[2], values: lut),
            couplers: Matrix3(rowMajor: couplers),
            enlarger: EnlargerSetup(baseIlluminant: baseIlluminant,
                                    dichroicFilters: dichroic,
                                    ccNeutral: SIMD3(cc[0], cc[1], cc[2])),
            scan: Scanning.Setup(viewingIlluminant: scanIlluminant,
                                 cmfs: cmfs,
                                 normalization: normalization[0],
                                 xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                 roundtrip: ColourMatrix(rowMajor: roundtrip),
                                 encode: true),
            midgrayDensity: midgray)
    }
}
