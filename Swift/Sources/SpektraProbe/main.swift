import Foundation
import SpektraCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// A smoke test for the package: proves the profile decoder, the golden blob and
// the resource bundling all work before any physics is written.
//
//   swift run spektra-probe

func mean(_ v: [Float]) -> Double {
    guard !v.isEmpty else { return 0 }
    return v.reduce(0.0) { $0 + Double($1) } / Double(v.count)
}

do {
    let film = try Profile.load(named: "kodak_portra_400")
    let paper = try Profile.load(named: "kodak_portra_endura")

    print("film  \(film.info.name) [\(film.info.type)]")
    print("      \(film.wavelengthCount) wavelengths, \(film.curveCount) curve samples, "
          + "reference illuminant \(film.info.referenceIlluminant)")
    print("paper \(paper.info.name) [\(paper.info.type)]")
    print("      \(paper.wavelengthCount) wavelengths, \(paper.curveCount) curve samples")

    let golden = try Golden.bundled()
    print("\ngolden arrays (\(golden.names().count)):")
    for name in golden.names() {
        guard let (shape, values) = golden.array(name) else { continue }
        let dims = shape.map(String.init).joined(separator: "×")
        let label = name.padding(toLength: 26, withPad: " ", startingAt: 0)
        let shapeLabel = dims.padding(toLength: 12, withPad: " ", startingAt: 0)
        print("  \(label) \(shapeLabel) mean \(String(format: "%+.6f", mean(values)))")
    }

    if let (shape, rgbIn) = golden.array("input.rgb") {
        print("\ninput \(shape) mean \(String(format: "%.6f", mean(rgbIn)))")
    }
    if let (shape, logE) = golden.array("taps.log_e_film") {
        print("log_e_film \(shape) mean \(String(format: "%.6f", mean(logE)))")
    }

    // Stage 1 end to end, against the Python reference.
    if let (inputShape, rgb) = golden.array("input.rgb"),
       let (_, expected) = golden.array("taps.log_e_film"),
       let (_, matrixValues) = golden.array("setup.colour_matrix_input_to_xyz"),
       let (lutShape, lutValues) = golden.array("setup.tc_lut") {
        let matrix = ColourMatrix(rowMajor: matrixValues)
        let table = ChromaTable(size: lutShape[0], channels: lutShape[2], values: lutValues)
        let got = FilmExposure.logExposure(rgb: rgb,
                                           width: inputShape[1],
                                           height: inputShape[0],
                                           matrix: matrix,
                                           table: table)
        var maxDiff: Float = 0
        for i in 0..<got.count { maxDiff = max(maxDiff, abs(got[i] - expected[i])) }
        print(String(format: "\nstage 1 (rgb -> log_e_film) max |diff| = %.3e", maxDiff))

        // Stage 2: log exposure -> CMY density on the negative.
        if let (_, curves) = golden.array("setup.film.density_curves"),
           let (_, exposure) = golden.array("setup.film.log_exposure"),
           let (_, couplers) = golden.array("setup.couplers_matrix"),
           let (_, expectedDensity) = golden.array("taps.cmy_film") {
            let curveSet = CharacteristicCurves(logExposure: exposure, densityCurves: curves)
            let density = FilmDevelopment.density(logExposure: got,
                                                  width: inputShape[1],
                                                  height: inputShape[0],
                                                  curves: curveSet,
                                                  couplers: Matrix3(rowMajor: couplers))
            var densityDiff: Float = 0
            for i in 0..<density.count {
                densityDiff = max(densityDiff, abs(density[i] - expectedDensity[i]))
            }
            print(String(format: "stage 2 (log_e_film -> cmy_film) max |diff| = %.3e", densityDiff))

            // Stage 3: negative density -> paper exposure.
            if let (_, channelDensity) = golden.array("setup.film.channel_density"),
               let (_, baseDensity) = golden.array("setup.film.base_density"),
               let (_, paperLogSensitivity) = golden.array("setup.print.log_sensitivity"),
               let (_, filtered) = golden.array("setup.enlarger.filtered_illuminant"),
               let (_, midgrayDensity) = golden.array("setup.enlarger.density_spectral_midgray"),
               let (_, expectedPrint) = golden.array("taps.log_e_print") {
                let sensitivity = PrintingExposure.linearSensitivity(paperLogSensitivity)
                let factor = PrintingExposure.midgrayFactor(midgrayDensity: midgrayDensity,
                                                            filteredIlluminant: filtered,
                                                            paperSensitivity: sensitivity)
                let printExposure = PrintingExposure.logExposure(cmy: density,
                                                                 width: inputShape[1],
                                                                 height: inputShape[0],
                                                                 filmChannelDensity: channelDensity,
                                                                 filmBaseDensity: baseDensity,
                                                                 paperSensitivity: sensitivity,
                                                                 filteredIlluminant: filtered,
                                                                 midgrayFactor: factor)
                var printDiff: Float = 0
                for i in 0..<printExposure.count {
                    printDiff = max(printDiff, abs(printExposure[i] - expectedPrint[i]))
                }
                print(String(format: "stage 3 (cmy_film -> log_e_print) max |diff| = %.3e", printDiff))

                // Stage 4: paper exposure -> print density (fitted curve model).
                if let model = paper.densityModel,
                   let (_, expectedDensityPrint) = golden.array("taps.cmy_print") {
                    let printDensity = PrintDevelopment.density(logExposure: printExposure,
                                                                width: inputShape[1],
                                                                height: inputShape[0],
                                                                exposureAxis: paper.logExposure,
                                                                model: model,
                                                                positive: paper.info.type == "positive")
                    var printDensityDiff: Float = 0
                    for i in 0..<printDensity.count {
                        printDensityDiff = max(printDensityDiff,
                                               abs(printDensity[i] - expectedDensityPrint[i]))
                    }
                    print(String(format: "stage 4 (log_e_print -> cmy_print) max |diff| = %.3e",
                                 printDensityDiff))

                    // Stage 5: print density -> output RGB.
                    if let (_, printChannelDensity) = golden.array("setup.print.channel_density"),
                       let (_, printBaseDensity) = golden.array("setup.print.base_density"),
                       let (_, scanIlluminant) = golden.array("setup.scan.illuminant"),
                       let (_, cmfs) = golden.array("setup.scan.cmfs"),
                       let (_, normalization) = golden.array("setup.scan.normalization"),
                       let (_, xyzToRGB) = golden.array("setup.scan.xyz_to_rgb"),
                       let (_, roundtrip) = golden.array("setup.scan.roundtrip_matrix"),
                       let (_, expectedRGB) = golden.array("taps.rgb_out") {
                        let rgb = Scanning.outputRGB(cmy: printDensity,
                                                     width: inputShape[1],
                                                     height: inputShape[0],
                                                     channelDensity: printChannelDensity,
                                                     baseDensity: printBaseDensity,
                                                     viewingIlluminant: scanIlluminant,
                                                     cmfs: cmfs,
                                                     normalization: normalization[0],
                                                     xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                                     roundtrip: ColourMatrix(rowMajor: roundtrip),
                                                     encode: true)
                        var rgbDiff: Float = 0
                        for i in 0..<rgb.count {
                            rgbDiff = max(rgbDiff, abs(rgb[i] - expectedRGB[i]))
                        }
                        print(String(format: "stage 5 (cmy_print -> rgb_out) max |diff| = %.3e",
                                     rgbDiff))
                    }

                    // One timed render, so a Mac and a phone can be compared.
                    if let benchmark = SelfTest.benchmark() {
                        print(String(format: "render 512x512: %.0f ms  (%.2f s / Mpx)",
                                     benchmark.milliseconds / 2,
                                     benchmark.millisecondsPerMegapixel / 1000))
                    }
                }
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
