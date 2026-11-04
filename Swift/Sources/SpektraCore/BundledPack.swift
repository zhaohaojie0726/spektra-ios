import Foundation

/// A baked film pack: one (film, paper, input space) combination with every
/// constant the simulator needs, plus the two profiles it refers to.
///
/// Packs are produced by `Reference/bake_packs.py` and verified there by
/// replaying the reference pipeline (max |diff| ~3e-7 after the float32
/// round-trip). A pack directory is the same container as the golden data:
/// `manifest.json` + `arrays.bin`, plus a `meta.json` naming the stocks.
public struct BundledPack {
    public let id: String
    public let film: Profile
    public let paper: Profile
    public let simulator: Simulator

    public static let defaultID = "kodak_portra_400__kodak_portra_endura"

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case unknownPack(String)

        public var description: String {
            switch self {
            case .missing(let name): return "pack is missing \(name)"
            case .unknownPack(let id): return "no pack called \(id)"
            }
        }
    }

    public init(id: String, film: Profile, paper: Profile, simulator: Simulator) {
        self.id = id
        self.film = film
        self.paper = paper
        self.simulator = simulator
    }

    /// Every pack shipped in the bundle, sorted.
    public static func availableIDs() -> [String] {
        guard let root = Bundle.module.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: root.path)
        else { return [] }
        return contents.filter { !$0.hasPrefix(".") }.sorted()
    }

    public static func load(id: String = defaultID) throws -> BundledPack {
        guard let root = Bundle.module.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        else { throw LoadError.unknownPack(id) }

        let bundle = try Golden.load(directory: root)
        guard let metaData = try? Data(contentsOf: root.appendingPathComponent("meta.json")),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let filmStock = meta["film"] as? String,
              let paperStock = meta["paper"] as? String
        else { throw LoadError.missing("meta.json") }

        let film = try Profile.load(named: filmStock)
        let paper = try Profile.load(named: paperStock)

        func array(_ name: String) throws -> [Float] {
            guard let (_, values) = bundle.array(name) else { throw LoadError.missing(name) }
            return values
        }

        guard let (shape, lut) = bundle.array("tc_lut") else {
            throw LoadError.missing("tc_lut")
        }
        // The pack's own input matrix. Packs are baked for Display P3, which is
        // what a photo decodes into on an iPhone; an sRGB-tagged file is
        // converted by Core Graphics on the way in, so both are correct.
        let matrix = try array("input_matrix")
        let couplers = try array("couplers_matrix")
        let baseIlluminant = try array("enlarger.base_illuminant")
        let dichroic = try array("enlarger.dichroic_filters")
        let cc = try array("enlarger.cc_neutral")
        let midgray = try array("enlarger.midgray_density")
        let scanIlluminant = try array("scan.illuminant")
        let cmfs = try array("scan.cmfs")
        let normalization = try array("scan.normalization")
        let xyzToRGB = try array("scan.xyz_to_rgb")
        let roundtrip = try array("scan.roundtrip_matrix")

        let simulator = Simulator(
            film: film,
            paper: paper,
            inputMatrix: ColourMatrix(rowMajor: matrix),
            chromaTable: ChromaTable(size: shape[0], channels: shape[2], values: lut),
            couplers: Matrix3(rowMajor: couplers),
            enlarger: EnlargerSetup(baseIlluminant: baseIlluminant,
                                    dichroicFilters: dichroic,
                                    ccNeutral: SIMD3(cc[0], cc[1], cc[2])),
            scan: Scanning.Setup(viewingIlluminant: scanIlluminant,
                                 cmfs: cmfs,
                                 normalization: normalization[0],
                                 xyzToRGB: ColourMatrix(rowMajor: xyzToRGB),
                                 roundtrip: ColourMatrix(rowMajor: roundtrip),
                                 encode: true),
            midgrayDensity: midgray)

        return BundledPack(id: id, film: film, paper: paper, simulator: simulator)
    }
}
