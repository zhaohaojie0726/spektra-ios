import XCTest
@testable import SpektraCore

final class Stage4Tests: XCTestCase {
    /// Fourth milestone: `taps.log_e_print → taps.cmy_print`.
    func testPrintDensityMatchesThePythonReference() throws {
        let golden = try Golden.bundled()
        let paper = try Profile.load(named: "kodak_portra_endura")
        guard let model = paper.densityModel else {
            return XCTFail("paper profile has no density_curves_model")
        }
        guard let (logShape, logE) = golden.array("taps.log_e_print"),
              let (_, expected) = golden.array("taps.cmy_print")
        else { return XCTFail("golden arrays missing") }

        let got = PrintDevelopment.density(logExposure: logE,
                                           width: logShape[1],
                                           height: logShape[0],
                                           exposureAxis: paper.logExposure,
                                           model: model,
                                           positive: paper.info.type == "positive")

        var maxDiff: Float = 0
        var meanDiff: Double = 0
        for i in 0..<got.count {
            let d = abs(got[i] - expected[i])
            meanDiff += Double(d)
            maxDiff = max(maxDiff, d)
        }
        meanDiff /= Double(got.count)
        print("stage4 max |diff| = \(maxDiff), mean = \(meanDiff)")
        XCTAssertLessThan(maxDiff, 2e-5)
        XCTAssertLessThan(meanDiff, 5e-6)
    }

    /// Documents why the model is evaluated instead of the stored curve array.
    func testFittedModelDiffersFromTheStoredSamples() throws {
        let paper = try Profile.load(named: "kodak_portra_endura")
        guard let model = paper.densityModel else {
            return XCTFail("paper profile has no density_curves_model")
        }
        let evaluated = model.evaluate(paper.logExposure, positive: false)
        var maxDiff: Float = 0
        for i in 0..<evaluated.count {
            maxDiff = max(maxDiff, abs(evaluated[i] - paper.densityCurves[i]))
        }
        print("model vs stored samples max |diff| = \(maxDiff)")
        XCTAssertGreaterThan(maxDiff, 1e-3, "the model and the samples should differ")
    }

    func testModelShape() throws {
        let paper = try Profile.load(named: "kodak_portra_endura")
        guard let model = paper.densityModel else {
            return XCTFail("missing model")
        }
        XCTAssertEqual(model.channelCount, 3)
        XCTAssertEqual(model.layersPerChannel, 3)
        XCTAssertEqual(model.modelType, "cdfs")
        // a normal CDF saturates: far left is ~0, far right ~1
        XCTAssertEqual(model.evaluate(-20, channel: 0, positive: false), 0, accuracy: 1e-4)
        let saturated = model.evaluate(20, channel: 0, positive: false)
        XCTAssertEqual(saturated, model.amplitudes[0].reduce(0, +), accuracy: 1e-4)
    }
}
