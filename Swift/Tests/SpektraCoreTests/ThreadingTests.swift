import XCTest
@testable import SpektraCore

final class ThreadingTests: XCTestCase {
    /// Row blocks are independent, so splitting them may not change a single
    /// pixel. If this ever fails the split has touched shared state.
    func testParallelStagesAreBitIdenticalToSerial() throws {
        let pack = try BundledPack.load()
        var input = [Float]()
        for i in 0..<(24 * 18 * 3) {
            input.append(0.02 + 0.96 * Float(i % 23) / 22)
        }

        var serial = pack.simulator
        serial.threads = 1
        var parallel = pack.simulator
        parallel.threads = 4

        let a = serial.render(linearRGB: input, width: 24, height: 18)
        let b = parallel.render(linearRGB: input, width: 24, height: 18)

        XCTAssertEqual(a.count, b.count)
        var maxDiff: Float = 0
        for i in 0..<a.count { maxDiff = max(maxDiff, abs(a[i] - b[i])) }
        print("serial vs parallel max |diff| = \(maxDiff)")
        XCTAssertEqual(maxDiff, 0, "row blocks must not change a pixel")
    }

    /// Strips are how a full-resolution export fits in memory; they must not
    /// change a pixel either.
    func testStripRenderingIsBitIdenticalToWholeFrame() throws {
        let pack = try BundledPack.load()
        var input = [Float]()
        for i in 0..<(20 * 14 * 3) {
            input.append(0.01 + 0.98 * Float(i % 19) / 18)
        }

        let whole = pack.simulator.render(linearRGB: input, width: 20, height: 14)
        let strips = pack.simulator.render(linearRGB: input, width: 20, height: 14, stripHeight: 3)

        XCTAssertEqual(whole.count, strips.count)
        var maxDiff: Float = 0
        for i in 0..<whole.count { maxDiff = max(maxDiff, abs(whole[i] - strips[i])) }
        print("whole vs strips max |diff| = \(maxDiff)")
        XCTAssertEqual(maxDiff, 0, "strips must not change a pixel")
    }
}
