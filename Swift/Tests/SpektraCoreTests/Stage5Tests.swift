import XCTest
@testable import SpektraCore

final class Stage5Tests: XCTestCase {
    /// Fifth milestone: `taps.cmy_print → taps.rgb_out`.
    func testOutputRGBMatchesThePythonReference() throws {
        let golden = try Golden.bundled()
        guard let (cmyShape, cmy) = golden.array("taps.cmy_print"),
              let (_, expected) = golden.array("taps.rgb_out"),
              let (_, channelDensity) = golden.array("setup.print.channel_density"),
              let (_, baseDensity) = golden.array("setup.print.base_density"),
              let (_, illuminant) = golden.array("setup.scan.illuminant"),
              let (_, cmfs) = golden.array("setup.scan.cmfs"),
              let (_, normalization) = golden.array("setup.scan.normalization"),
              let (_, xyzToRGB) = golden.array("setup.scan.xyz_to_rgb"),
              let (_, roundtrip) = golden.array("setup.scan.roundtrip_matrix")
        else { return XCTFail("golden arrays missing") }

        let got = Scanning.outputRGB(cmy: cmy,
                                     width: cmyShape[1],
                                     height: cmyShape[0],
                                     channelDensity: channelDensity,
                                     baseDensity: baseDensity,
                                     viewingIlluminant: illuminant,
                                     cmfs: cmfs,
                                     normalization: normalization[0],
                                     xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                     roundtrip: ColourMatrix(rowMajor: roundtrip),
                                     encode: true)

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            maxDiff = max(maxDiff, d)
        }
        meanDiff /= Double(got.count)
        print("stage5 max |diff| = \(maxDiff), mean = \(meanDiff)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    /// The same-space round trip is ~1e-4 of the output and must not be skipped
    /// (SpektraLab trap 7). This pins the magnitude so nobody "simplifies" it.
    func testRoundtripMatrixIsAlmostButNotQuiteIdentity() throws {
        let golden = try Golden.bundled()
        guard let (_, roundtrip) = golden.array("setup.scan.roundtrip_matrix") else {
            return XCTFail("roundtrip matrix missing")
        }
        let identity: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        var maxDiff: Float = 0
        for i in 0..<9 { maxDiff = max(maxDiff, abs(roundtrip[i] - identity[i])) }
        XCTAssertGreaterThan(maxDiff, 1e-6, "matrix should not be exactly identity")
        XCTAssertLessThan(maxDiff, 1e-3)
    }

    func testSRGBEncodingEndpoints() {
        XCTAssertEqual(Scanning.srgbEncode(0), 0, accuracy: 1e-7)
        XCTAssertEqual(Scanning.srgbEncode(1), 1, accuracy: 1e-6)
        XCTAssertEqual(Scanning.srgbEncode(0.0031308), 0.04045, accuracy: 2e-3)
        XCTAssertEqual(Scanning.srgbEncode(0.18), 0.4613, accuracy: 1e-3)
    }
}
