import XCTest
@testable import SpektraCore

final class BundledPackTests: XCTestCase {
    func testDefaultPackLoadsAndRenders() throws {
        let pack = try BundledPack.load()
        XCTAssertEqual(pack.film.info.stock, "kodak_portra_400")
        XCTAssertEqual(pack.paper.info.stock, "kodak_portra_endura")

        // a small neutral ramp
        var input = [Float]()
        for _ in 0..<4 {
            for column in 0..<8 {
                let value = Float(column) / 7.0
                input.append(contentsOf: [value, value, value])
            }
        }
        let out = pack.simulator.render(linearRGB: input, width: 8, height: 4)
        XCTAssertEqual(out.count, input.count)
        for value in out {
            XCTAssertTrue(value.isFinite, "non-finite output")
        }

        // the reference renders this ramp as roughly 0.05 -> 0.85
        let first = out[0]
        let last = out[(8 * 3) - 2]
        XCTAssertGreaterThan(last, first)
        XCTAssertGreaterThan(last - first, 0.3)
        XCTAssertLessThan(last, 1.01)
    }

    /// Every shipped pack must load and render — a new stock that bakes wrong
    /// fails here rather than on a phone.
    func testAllPacksLoadAndRender() throws {
        let identifiers = BundledPack.availableIDs()
        XCTAssertGreaterThanOrEqual(identifiers.count, 3, "expected the three baked packs")

        for identifier in identifiers {
            let pack = try BundledPack.load(id: identifier)
            XCTAssertFalse(pack.film.info.stock.isEmpty, identifier)
            XCTAssertFalse(pack.paper.info.stock.isEmpty, identifier)

            let input = [Float](repeating: 0.18, count: 4 * 4 * 3)
            let out = pack.simulator.render(linearRGB: input, width: 4, height: 4)
            XCTAssertEqual(out.count, input.count, identifier)
            for value in out {
                XCTAssertTrue(value.isFinite, "\(identifier) produced a non-finite value")
            }
            // an 18 % grey must land in the middle of the print, not at an end
            let middle = out[1]
            XCTAssertGreaterThan(middle, 0.1, identifier)
            XCTAssertLessThan(middle, 0.95, identifier)
        }
    }

    /// Different stocks must actually look different — otherwise a baking bug
    /// could ship three copies of the same pack and every test would pass.
    func testDifferentStocksRenderDifferently() throws {
        var input = [Float]()
        for i in 0..<(16 * 16 * 3) {
            input.append(0.02 + 0.9 * Float(i % 29) / 28)
        }

        let identifiers = BundledPack.availableIDs()
        guard identifiers.count >= 2 else { return XCTFail("need two packs") }

        let first = try BundledPack.load(id: identifiers[0])
            .simulator.render(linearRGB: input, width: 16, height: 16)

        for identifier in identifiers.dropFirst() {
            let other = try BundledPack.load(id: identifier)
                .simulator.render(linearRGB: input, width: 16, height: 16)
            var maxDiff: Float = 0
            for i in 0..<first.count { maxDiff = max(maxDiff, abs(first[i] - other[i])) }
            print("\(identifiers[0]) vs \(identifier): max |diff| = \(maxDiff)")
            XCTAssertGreaterThan(maxDiff, 0.02, "\(identifier) renders like \(identifiers[0])")
        }
    }
}
