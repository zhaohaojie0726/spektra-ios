import XCTest
@testable import SpektraCore

final class Stage2Tests: XCTestCase {
    /// Second milestone: `taps.log_e_film → taps.cmy_film`.
    func testDensityMatchesThePythonReference() throws {
        let golden = try Golden.bundled()

        guard let (logShape, logE) = golden.array("taps.log_e_film"),
              let (_, expected) = golden.array("taps.cmy_film"),
              let (_, exposure) = golden.array("setup.film.log_exposure"),
              let (curveShape, curveValues) = golden.array("setup.film.density_curves"),
              let (matrixShape, matrixValues) = golden.array("setup.couplers_matrix")
        else { return XCTFail("golden arrays missing") }

        XCTAssertEqual(logShape.count, 3)
        XCTAssertEqual(curveShape, [256, 3])
        XCTAssertEqual(matrixShape, [3, 3])

        let curves = CharacteristicCurves(logExposure: exposure, densityCurves: curveValues)
        let couplers = Matrix3(rowMajor: matrixValues)
        let got = FilmDevelopment.density(logExposure: logE,
                                          width: logShape[1],
                                          height: logShape[0],
                                          curves: curves,
                                          couplers: couplers)

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        var worst = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            if d > maxDiff { maxDiff = d; worst = i }
        }
        meanDiff /= Double(got.count)
        print("stage2 max |diff| = \(maxDiff), mean = \(meanDiff), worst index \(worst)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    /// The Swift defaults must reproduce the matrix the reference builds.
    func testCouplerMatrixMatchesTheReference() throws {
        let golden = try Golden.bundled()
        guard let (_, expected) = golden.array("setup.couplers_matrix") else {
            return XCTFail("couplers matrix missing")
        }
        let ours = DirCouplerParams().matrix()
        let values = [ours.row0.x, ours.row0.y, ours.row0.z,
                      ours.row1.x, ours.row1.y, ours.row1.z,
                      ours.row2.x, ours.row2.y, ours.row2.z]
        for i in 0..<9 {
            XCTAssertEqual(values[i], expected[i], accuracy: 1e-6, "element \(i)")
        }
    }

    func testCurvesAreNormalisedToZeroAtTheToe() {
        let film = try? Profile.load(named: "kodak_portra_400")
        guard let film else { return XCTFail("profile missing") }
        let curves = CharacteristicCurves(logExposure: film.logExposure,
                                          densityCurves: film.densityCurves)
        for channel in 0..<3 {
            var minimum = Float.greatestFiniteMagnitude
            for k in 0..<curves.exposure.count {
                minimum = min(minimum, curves.densities[k * 3 + channel])
            }
            XCTAssertEqual(minimum, 0, accuracy: 1e-6)
        }
    }

    func testLookupClampsOutsideTheAxis() {
        // nodes at -3, 0, 4; channel 2 is the interesting one
        let curves = CharacteristicCurves(exposure: [-3, 0, 4],
                                          densities: [0, 0, 1.0,
                                                      0, 0.4, 0.9,
                                                      0, 0.3, 0.8])
        XCTAssertEqual(curves.value(-10, channel: 2), 1.0, accuracy: 1e-6)
        XCTAssertEqual(curves.value(10, channel: 2), 0.8, accuracy: 1e-6)
        // right-biased: at an exact node the value is the node's own
        XCTAssertEqual(curves.value(0, channel: 1), 0.4, accuracy: 1e-6)
        // halfway between the first two nodes
        XCTAssertEqual(curves.value(-1.5, channel: 2), 0.95, accuracy: 1e-6)
    }
}
