import XCTest
@testable import SpektraCore

final class Stage1Tests: XCTestCase {
    /// The first milestone: linear RGB → `taps.log_e_film`.
    ///
    /// The bar is 2e-5 because the Swift core runs in Float while the golden
    /// was produced in Float64; the algorithm itself is exact.
    func testLogExposureMatchesThePythonReference() throws {
        let golden = try Golden.bundled()

        guard let (inputShape, rgb) = golden.array("input.rgb"),
              let (_, expected) = golden.array("taps.log_e_film"),
              let (matrixShape, matrixValues) = golden.array("setup.colour_matrix_input_to_xyz"),
              let (lutShape, lutValues) = golden.array("setup.tc_lut")
        else { return XCTFail("golden arrays missing") }

        XCTAssertEqual(inputShape.count, 3)
        let height = inputShape[0], width = inputShape[1]
        XCTAssertEqual(matrixShape, [3, 3])
        XCTAssertEqual(lutShape.count, 3)
        XCTAssertEqual(lutShape[0], lutShape[1])

        let matrix = ColourMatrix(rowMajor: matrixValues)
        let table = ChromaTable(size: lutShape[0], channels: lutShape[2], values: lutValues)

        let got = FilmExposure.logExposure(rgb: rgb, width: width, height: height,
                                          matrix: matrix, table: table)

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        var worstIndex = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            if d > maxDiff { maxDiff = d; worstIndex = i }
        }
        meanDiff /= Double(got.count)

        print("stage1 max |diff| = \(maxDiff), mean = \(meanDiff), worst index \(worstIndex)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    func testMitchellWeightsMatchTheReferenceAtKnownPoints() {
        // w(0) = 2/3, w(1) = w(-1) = 1/6, w(2) = w(-2) = 0 for B = C = 1/3
        XCTAssertEqual(ChromaTable.mitchellWeight(0), 2.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(ChromaTable.mitchellWeight(1), 1.0 / 6.0, accuracy: 1e-6)
        XCTAssertEqual(ChromaTable.mitchellWeight(-1), 1.0 / 6.0, accuracy: 1e-6)
        XCTAssertEqual(ChromaTable.mitchellWeight(2), 0, accuracy: 1e-6)
    }

    func testReflectionAndClampingMatchTheReference() {
        XCTAssertEqual(ChromaTable.reflectedIndex(-1, 192), 1)
        XCTAssertEqual(ChromaTable.reflectedIndex(0, 192), 0)
        XCTAssertEqual(ChromaTable.reflectedIndex(191, 192), 191)
        XCTAssertEqual(ChromaTable.reflectedIndex(192, 192), 190)

        let (base, frac) = ChromaTable.baseAndFraction(0, 192)
        XCTAssertEqual(base, 0)
        XCTAssertEqual(frac, 0, accuracy: 1e-7)

        let (edgeBase, edgeFrac) = ChromaTable.baseAndFraction(191, 192)
        XCTAssertEqual(edgeBase, 190)
        XCTAssertEqual(edgeFrac, 1, accuracy: 1e-7)

        let (nanBase, _) = ChromaTable.baseAndFraction(.nan, 192)
        XCTAssertEqual(nanBase, 0)
    }
}
