import XCTest
@testable import SpektraCore

final class ProfileTests: XCTestCase {
    func testFilmProfileLoads() throws {
        let film = try Profile.load(named: "kodak_portra_400")
        XCTAssertEqual(film.info.stock, "kodak_portra_400")
        XCTAssertEqual(film.info.type, "negative")
        XCTAssertEqual(film.info.support, "film")
        XCTAssertEqual(film.info.referenceIlluminant, "D55")
        XCTAssertEqual(film.wavelengthCount, 81)
        XCTAssertEqual(film.curveCount, 256)
        XCTAssertEqual(film.logSensitivity.count, 81 * 3)
        XCTAssertEqual(film.channelDensity.count, 81 * 3)
        XCTAssertEqual(film.baseDensity.count, 81)
        XCTAssertEqual(film.densityCurves.count, 256 * 3)
        XCTAssertEqual(film.wavelengths.first!, 380, accuracy: 1e-3)
        XCTAssertEqual(film.wavelengths.last!, 780, accuracy: 1e-3)
    }

    func testPaperProfileLoads() throws {
        let paper = try Profile.load(named: "kodak_portra_endura")
        XCTAssertEqual(paper.info.support, "paper")
        XCTAssertEqual(paper.wavelengthCount, 81)
        XCTAssertEqual(paper.curveCount, 256)
    }

    func testGoldenArraysAreWellFormed() throws {
        let golden = try Golden.bundled()
        XCTAssertGreaterThanOrEqual(golden.names().count, 15)

        guard let input = golden.array("input.rgb") else {
            return XCTFail("input.rgb missing")
        }
        XCTAssertEqual(input.shape, [24, 32, 3])
        XCTAssertEqual(input.values.count, 24 * 32 * 3)

        guard let logE = golden.array("taps.log_e_film") else {
            return XCTFail("taps.log_e_film missing")
        }
        XCTAssertEqual(logE.shape, [24, 32, 3])

        // every array must lie inside the blob: offsets are validated on read,
        // so a nil here means the manifest disagrees with arrays.bin
        for name in golden.names() {
            XCTAssertNotNil(golden.array(name), "array \(name) out of bounds")
        }
    }

    func testGoldenInputMatchesSyntheticImage() throws {
        let golden = try Golden.bundled()
        guard let (_, rgb) = golden.array("input.rgb") else {
            return XCTFail("input.rgb missing")
        }
        // the exporter writes black, 18% grey and white anchors into the first row
        XCTAssertEqual(rgb[0], 0.0, accuracy: 1e-6)
        XCTAssertEqual(rgb[3], 0.18, accuracy: 1e-6)
        XCTAssertEqual(rgb[6], 1.0, accuracy: 1e-6)
    }
}
