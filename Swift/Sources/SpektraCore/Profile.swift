import Foundation

/// One spektrafilm profile: an 81-wavelength spectral description of a film or
/// a paper, plus its 256-sample characteristic curves.
///
/// The JSON on disk is the upstream `spektrafilm` profile (`metadata`, `info`,
/// `data`). Everything is decoded into flat `Float` arrays; the shape is carried
/// by the `*Count` properties so callers index `[index * channels + channel]`.
public struct Profile {
    public struct Info {
        public let stock: String
        public let name: String
        public let type: String                 // "negative" | "positive"
        public let support: String              // "film" | "paper"
        public let channelModel: String         // "color" | "bw"
        public let referenceIlluminant: String
        public let viewingIlluminant: String

        public init(stock: String, name: String, type: String, support: String,
                    channelModel: String, referenceIlluminant: String,
                    viewingIlluminant: String) {
            self.stock = stock
            self.name = name
            self.type = type
            self.support = support
            self.channelModel = channelModel
            self.referenceIlluminant = referenceIlluminant
            self.viewingIlluminant = viewingIlluminant
        }
    }

    public let info: Info

    /// 81 wavelengths, 380…780 nm in 5 nm steps.
    public let wavelengths: [Float]
    public var wavelengthCount: Int { wavelengths.count }

    /// 81 × 3 log10 sensitivities.
    public let logSensitivity: [Float]
    /// 81 × 3 dye densities (per channel, per wavelength).
    public let channelDensity: [Float]
    /// 81 base (unexposed) densities.
    public let baseDensity: [Float]

    /// 256 log-exposure samples, −3…4.
    public let logExposure: [Float]
    /// 256 × 3 characteristic curves.
    public let densityCurves: [Float]

    /// The parametric curves the runtime actually evaluates for prints.
    public let densityModel: DensityCurveModel?

    public var curveCount: Int { logExposure.count }

    /// Builds a profile from parts — the JSON loader and the tests both use it.
    public init(info: Info,
                wavelengths: [Float],
                logSensitivity: [Float],
                channelDensity: [Float],
                baseDensity: [Float],
                logExposure: [Float],
                densityCurves: [Float],
                densityModel: DensityCurveModel?) {
        self.info = info
        self.wavelengths = wavelengths
        self.logSensitivity = logSensitivity
        self.channelDensity = channelDensity
        self.baseDensity = baseDensity
        self.logExposure = logExposure
        self.densityCurves = densityCurves
        self.densityModel = densityModel
    }

    public enum LoadError: Error, CustomStringConvertible {
        case file(String)
        case malformed(String)
        case missing(String)

        public var description: String {
            switch self {
            case .file(let path): return "cannot read profile at \(path)"
            case .malformed(let what): return "malformed profile: \(what)"
            case .missing(let key): return "profile is missing '\(key)'"
            }
        }
    }

    public static func load(contentsOf url: URL) throws -> Profile {
        guard let data = try? Data(contentsOf: url) else {
            throw LoadError.file(url.path)
        }
        return try Profile(jsonData: data)
    }

    public static func load(named name: String) throws -> Profile {
        guard let base = Bundle.module.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        else { throw LoadError.file("Resources/profiles") }
        let url = base.appendingPathComponent(name).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.file(url.path)
        }
        return try load(contentsOf: url)
    }

    public init(jsonData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw LoadError.malformed("root is not an object") }
        guard let infoJSON = root["info"] as? [String: Any] else {
            throw LoadError.missing("info")
        }
        guard let dataJSON = root["data"] as? [String: Any] else {
            throw LoadError.missing("data")
        }

        info = Info(
            stock: infoJSON["stock"] as? String ?? "",
            name: infoJSON["name"] as? String ?? "",
            type: infoJSON["type"] as? String ?? "negative",
            support: infoJSON["support"] as? String ?? "film",
            channelModel: infoJSON["channel_model"] as? String ?? "color",
            referenceIlluminant: infoJSON["reference_illuminant"] as? String ?? "D55",
            viewingIlluminant: infoJSON["viewing_illuminant"] as? String ?? "D50"
        )

        wavelengths = try Profile.floats(dataJSON["wavelengths"], key: "wavelengths")
        logSensitivity = try Profile.floats(dataJSON["log_sensitivity"], key: "log_sensitivity")
        channelDensity = try Profile.floats(dataJSON["channel_density"], key: "channel_density")
        baseDensity = try Profile.floats(dataJSON["base_density"], key: "base_density")
        logExposure = try Profile.floats(dataJSON["log_exposure"], key: "log_exposure")
        densityCurves = try Profile.floats(dataJSON["density_curves"], key: "density_curves")
        densityModel = DensityCurveModel.parse(dataJSON["density_curves_model"])

        guard wavelengthCount > 0, logSensitivity.count == wavelengthCount * 3,
              channelDensity.count == wavelengthCount * 3,
              baseDensity.count == wavelengthCount,
              curveCount > 1, densityCurves.count == curveCount * 3
        else { throw LoadError.malformed("array shapes disagree") }
    }

    /// Recursively flattens a JSON array of numbers (or arrays of numbers).
    private static func floats(_ value: Any?, key: String) throws -> [Float] {
        guard let value else { throw LoadError.missing(key) }
        var out: [Float] = []
        if !flatten(value, into: &out) { throw LoadError.malformed("\(key) is not numeric") }
        return out
    }

    private static func flatten(_ value: Any, into out: inout [Float]) -> Bool {
        if let n = value as? NSNumber { out.append(n.floatValue); return true }
        if let arr = value as? [Any] {
            for v in arr where !flatten(v, into: &out) { return false }
            return true
        }
        return false
    }
}
