import Foundation

/// Reads the golden data exported by `Reference/export_goldens.py`.
///
/// Layout: `manifest.json` holds `{"arrays": {name: {"shape": [...], "offset": n}}}`
/// and `arrays.bin` is one little-endian float32 blob. Offsets are in floats.
public struct Golden {
    public struct Entry {
        public let shape: [Int]
        public let offset: Int
        public var count: Int { shape.reduce(1, *) }
    }

    public let entries: [String: Entry]
    private let blob: [Float]

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case malformed(String)
        public var description: String {
            switch self {
            case .missing(let p): return "golden data missing: \(p)"
            case .malformed(let m): return "golden data malformed: \(m)"
            }
        }
    }

    public static func load(directory: URL) throws -> Golden {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let binURL = directory.appendingPathComponent("arrays.bin")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let blobData = try? Data(contentsOf: binURL)
        else { throw LoadError.missing(directory.path) }

        guard let root = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let arrays = root["arrays"] as? [String: Any]
        else { throw LoadError.malformed("manifest root") }

        var entries: [String: Entry] = [:]
        for (name, value) in arrays {
            guard let obj = value as? [String: Any],
                  let shape = obj["shape"] as? [NSNumber],
                  let offset = obj["offset"] as? NSNumber
            else { throw LoadError.malformed("entry \(name)") }
            entries[name] = Entry(shape: shape.map { $0.intValue }, offset: offset.intValue)
        }

        var blob = [Float](repeating: 0, count: blobData.count / 4)
        blobData.withUnsafeBytes { source in
            for i in 0..<blob.count {
                // `loadUnaligned` because Data's storage is not guaranteed to be
                // 4-byte aligned; binding it to Float and indexing would be UB.
                blob[i] = source.loadUnaligned(fromByteOffset: i * 4, as: Float.self)
            }
        }
        guard blob.count * 4 == blobData.count else {
            throw LoadError.malformed("arrays.bin is not a multiple of 4 bytes")
        }
        return Golden(entries: entries, blob: blob)    }

    public static func bundled() throws -> Golden {
        guard let url = Bundle.module.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("goldens", isDirectory: true)
        else { throw LoadError.missing("Resources/goldens") }
        return try load(directory: url)
    }

    public func names() -> [String] { entries.keys.sorted() }

    /// Returns the array as a flat `[Float]` in row-major order.
    public func array(_ name: String) -> (shape: [Int], values: [Float])? {
        guard let e = entries[name] else { return nil }
        let end = e.offset + e.count
        guard e.offset >= 0, end <= blob.count else { return nil }
        return (e.shape, Array(blob[e.offset..<end]))
    }

    public func doubleArray(_ name: String) -> (shape: [Int], values: [Double])? {
        guard let (shape, values) = array(name) else { return nil }
        return (shape, values.map(Double.init))
    }
}
