import Dispatch
import Foundation
import ImageIO

/// A small command-line front end, so the pipeline can be checked on a Mac
/// without building the iOS app at all.
///
///     swift run spektra-cli photo.heic out.png
///     swift run spektra-cli photo.heic out.png --pack kodak_ektar_100__kodak_portra_endura \
///         --ev 0.3 --magenta 5 --yellow -5 --print 1.05 --max-edge 2400
///
/// Every step it takes is the same code the app takes; only the file handling
/// differs.
enum CLI {
    static func run() {
        var positional: [String] = []
        var pack = BundledPack.defaultID
        var exposureEV: Float = 0
        var magenta: Float = 0
        var yellow: Float = 0
        var printExposure: Float = 1
        var maxEdge = 0
        var threads = 0

        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--pack":
                pack = arguments.first ?? pack
                if !arguments.isEmpty { arguments.removeFirst() }
            case "--ev":
                exposureEV = Float(take(&arguments) ?? "0") ?? 0
            case "--magenta":
                magenta = Float(take(&arguments) ?? "0") ?? 0
            case "--yellow":
                yellow = Float(take(&arguments) ?? "0") ?? 0
            case "--print":
                printExposure = Float(take(&arguments) ?? "1") ?? 1
            case "--max-edge":
                maxEdge = Int(take(&arguments) ?? "0") ?? 0
            case "--threads":
                threads = Int(take(&arguments) ?? "0") ?? 0
            case "--packs":
                for identifier in BundledPack.availableIDs() { print(identifier) }
                exit(0)
            case "-h", "--help":
                usage()
                exit(0)
            default:
                positional.append(argument)
            }
        }

        // `--bench <edge>` needs no photo: it renders a synthetic frame, so the
        // speed question can be answered on any machine.
        if let benchIndex = positional.firstIndex(of: "--bench") {
            let edge = positional.count > benchIndex + 1 ? Int(positional[benchIndex + 1]) ?? 1024 : 1024
            benchmark(edge: edge, pack: pack, threads: threads)
            exit(0)
        }

        guard positional.count >= 2 else {
            usage()
            exit(2)
        }
        let inputPath = positional[0]
        let outputPath = positional[1]

        guard let data = FileManager.default.contents(atPath: inputPath) else {
            fail("cannot read \(inputPath)")
        }
        let packStart = DispatchTime.now()
        guard let bundle = try? BundledPack.load(id: pack) else {
            fail("cannot load pack \(pack) — try --packs")
        }
        let packMilliseconds = elapsed(since: packStart)

        let decodeStart = DispatchTime.now()
        guard let frame = ImageBridge.linearRGB(from: data, maxEdge: maxEdge) else {
            fail("cannot decode \(inputPath)")
        }
        let decodeMilliseconds = elapsed(since: decodeStart)

        var simulator = bundle.simulator
        simulator.exposureCompensationEV = exposureEV
        simulator.filterShift = SIMD3(0, magenta, yellow)
        simulator.printExposure = printExposure
        simulator.threads = threads

        let renderStart = DispatchTime.now()
        let rgb = simulator.render(linearRGB: frame.pixels,
                                   width: frame.width,
                                   height: frame.height)
        let renderMilliseconds = elapsed(since: renderStart)

        let writeStart = DispatchTime.now()
        guard let image = ImageBridge.makeImage(fromRGB: rgb,
                                                width: frame.width,
                                                height: frame.height)
        else { fail("cannot build the output image") }
        guard writePNG(image, to: outputPath) else {
            fail("cannot write \(outputPath)")
        }
        let writeMilliseconds = elapsed(since: writeStart)

        let megapixels = Double(frame.width * frame.height) / 1e6
        let perMegapixel = renderMilliseconds / max(megapixels, 0.001)
        print("\(frame.width)x\(frame.height)  (\(String(format: "%.1f", megapixels)) MP)")
        print("  pack    \(pack)   \(String(format: "%.0f", packMilliseconds)) ms")
        print("  decode  \(String(format: "%.0f", decodeMilliseconds)) ms")
        print("  render  \(String(format: "%.0f", renderMilliseconds)) ms  "
              + "(\(String(format: "%.2f", perMegapixel / 1000)) s/MP)")
        print("  write   \(String(format: "%.0f", writeMilliseconds)) ms")
        print("  -> \(outputPath)")
    }

    /// Renders a synthetic `edge × edge` frame and reports the wall clock.
    static func benchmark(edge: Int, pack: String, threads: Int) {
        guard let bundle = try? BundledPack.load(id: pack) else {
            fail("cannot load pack \(pack) — try --packs")
        }
        var input = [Float](repeating: 0, count: edge * edge * 3)
        for y in 0..<edge {
            for x in 0..<edge {
                let i = (y * edge + x) * 3
                let u = Float(x) / Float(max(edge - 1, 1))
                let v = Float(y) / Float(max(edge - 1, 1))
                input[i] = u * v
                input[i + 1] = u
                input[i + 2] = v
            }
        }

        var simulator = bundle.simulator
        simulator.threads = threads
        _ = simulator.render(linearRGB: input, width: edge, height: edge)  // warm-up

        let start = DispatchTime.now()
        _ = simulator.render(linearRGB: input, width: edge, height: edge)
        let milliseconds = elapsed(since: start)
        let megapixels = Double(edge * edge) / 1e6

        print("\(edge)x\(edge)  (\(String(format: "%.2f", megapixels)) MP)")
        print("  render  \(String(format: "%.0f", milliseconds)) ms  "
              + "(\(String(format: "%.2f", milliseconds / megapixels / 1000)) s/MP)")
        print("  threads \(threads == 0 ? "auto" : String(threads))")
    }

    /// Consumes the next argument, if any.
    static func take(_ arguments: inout [String]) -> String? {
        guard !arguments.isEmpty else { return nil }
        return arguments.removeFirst()
    }

    static func usage() {
        print("""
        usage: spektra-cli <input.heic|.jpg|.png|.tif> <output.png> [options]

          --pack <id>     a pack from --packs (default \(BundledPack.defaultID))
          --ev <float>    exposure compensation, stops
          --magenta <cc>  enlarger magenta shift, CC units
          --yellow <cc>   enlarger yellow shift, CC units
          --print <f>     print exposure multiplier
          --max-edge <n>  downscale the input before rendering (0 = full size)
          --threads <n>   0 = one block per core
          --packs         list the packs in the bundle
          --bench [edge]  render a synthetic frame and report the time (no photo needed)
        """)
    }

    static func writePNG(_ image: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                 "public.png" as CFString,
                                                                 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    static func elapsed(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}

CLI.run()
