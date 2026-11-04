import XCTest
@testable import SpektraCore

final class Stage3Tests: XCTestCase {
    /// Third milestone: `taps.cmy_film → taps.log_e_print`.
    func testPaperExposureMatchesThePythonReference() throws {
        let golden = try Golden.bundled()
        guard let (cmyShape, cmy) = golden.array("taps.cmy_film"),
              let (_, expected) = golden.array("taps.log_e_print"),
              let (_, channelDensity) = golden.array("setup.film.channel_density"),
              let (_, baseDensity) = golden.array("setup.film.base_density"),
              let (_, paperLogSensitivity) = golden.array("setup.print.log_sensitivity"),
              let (_, filtered) = golden.array("setup.enlarger.filtered_illuminant"),
              let (_, midgrayDensity) = golden.array("setup.enlarger.density_spectral_midgray")
        else { return XCTFail("golden arrays missing") }

        let sensitivity = PrintingExposure.linearSensitivity(paperLogSensitivity)
        let factor = PrintingExposure.midgrayFactor(midgrayDensity: midgrayDensity,
                                                    filteredIlluminant: filtered,
                                                    paperSensitivity: sensitivity)
        let got = PrintingExposure.logExposure(cmy: cmy,
                                               width: cmyShape[1],
                                               height: cmyShape[0],
                                               filmChannelDensity: channelDensity,
                                               filmBaseDensity: baseDensity,
                                               paperSensitivity: sensitivity,
                                               filteredIlluminant: filtered,
                                               midgrayFactor: factor)

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            maxDiff = max(maxDiff, d)
        }
        meanDiff /= Double(got.count)
        print("stage3 max |diff| = \(maxDiff), mean = \(meanDiff)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    /// The dichroic filter model has to rebuild the filtered lamp spectrum the
    /// reference used, otherwise every print is quietly re-balanced.
    func testFilteredIlluminantMatchesTheReference() throws {
        let golden = try Golden.bundled()
        guard let (_, base) = golden.array("setup.enlarger.base_illuminant"),
              let (_, filters) = golden.array("setup.enlarger.dichroic_filters"),
              let (_, cc) = golden.array("setup.enlarger.cc_neutral"),
              let (_, expected) = golden.array("setup.enlarger.filtered_illuminant")
        else { return XCTFail("enlarger arrays missing") }

        let setup = EnlargerSetup(baseIlluminant: base,
                                  dichroicFilters: filters,
                                  ccNeutral: SIMD3(cc[0], cc[1], cc[2]))
        let filtered = setup.filteredIlluminant(cc: setup.ccNeutral)
        var maxDiff: Float = 0
        for i in 0..<filtered.count {
            maxDiff = max(maxDiff, abs(filtered[i] - expected[i]))
        }
        print("filtered illuminant max |diff| = \(maxDiff)")
        XCTAssertLessThan(maxDiff, 1e-5)
    }

    func testSensitivityConversionHandlesNaN() {
        let linear = PrintingExposure.linearSensitivity([0, .nan, -1])
        XCTAssertEqual(linear[0], 1, accuracy: 1e-6)
        XCTAssertEqual(linear[1], 0, accuracy: 1e-6)
        XCTAssertEqual(linear[2], 0.1, accuracy: 1e-6)
    }
}
