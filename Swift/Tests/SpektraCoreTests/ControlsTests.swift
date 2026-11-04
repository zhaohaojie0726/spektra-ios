import XCTest
@testable import SpektraCore

final class ControlsTests: XCTestCase {
    /// Exposure compensation must be exactly a gain on the linear input.
    /// Verified against the reference: EV = +1 renders bit-identically to a
    /// frame whose input was doubled (with the enlarger compensation off, which
    /// is what the packs bake).
    func testExposureCompensationEqualsInputGain() throws {
        let pack = try BundledPack.load()
        var input = [Float]()
        for i in 0..<(6 * 6 * 3) {
            input.append(0.05 + 0.9 * Float(i % 17) / 16)
        }

        var shifted = pack.simulator
        shifted.exposureCompensationEV = 1
        let a = shifted.render(linearRGB: input, width: 6, height: 6)

        let doubled = input.map { $0 * 2 }
        let b = pack.simulator.render(linearRGB: doubled, width: 6, height: 6)

        var maxDiff: Float = 0
        for i in 0..<a.count { maxDiff = max(maxDiff, abs(a[i] - b[i])) }
        print("EV vs input gain max |diff| = \(maxDiff)")
        XCTAssertLessThan(maxDiff, 1e-5)
    }

    func testPrintExposureBrightens() throws {
        let pack = try BundledPack.load()
        let input = [Float](repeating: 0.18, count: 16 * 3)

        var brighter = pack.simulator
        brighter.printExposure = 2
        let a = pack.simulator.render(linearRGB: input, width: 4, height: 4)
        let b = brighter.render(linearRGB: input, width: 4, height: 4)

        XCTAssertGreaterThan(b[1], a[1])
        XCTAssertLessThan(b[1], 1.01)
    }

    func testFilterShiftMovesThePrint() throws {
        let pack = try BundledPack.load()
        let input = [Float](repeating: 0.18, count: 16 * 3)
        var shifted = pack.simulator
        shifted.filterShift = SIMD3(0, 10, 0)

        let a = pack.simulator.render(linearRGB: input, width: 4, height: 4)
        let b = shifted.render(linearRGB: input, width: 4, height: 4)
        var maxDiff: Float = 0
        for i in 0..<a.count { maxDiff = max(maxDiff, abs(a[i] - b[i])) }
        XCTAssertGreaterThan(maxDiff, 1e-4)
        XCTAssertLessThan(maxDiff, 0.25)
    }
}
