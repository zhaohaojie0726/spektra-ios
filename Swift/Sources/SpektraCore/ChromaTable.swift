import Foundation

/// A 2-D lookup table of spectra-derived values, indexed by the square
/// coordinates `(tx, ty)` from `triangularToSquare`, sampled with the same
/// Mitchell-Netravali cubic the reference uses (`_cubic_interp_lut_at_2d`).
///
/// The table for a film stock is `192 × 192 × 3`: the Hanatos 2025 spectra LUT
/// contracted against the stock's sensitivities, with the input gamut
/// compression already baked in. It is built once per film (see
/// `Reference/export_goldens.py`) and never changes per pixel.
public struct ChromaTable {
    public let size: Int
    public let channels: Int
    /// Row-major `[i * size * channels + j * channels + c]`.
    public let values: [Float]

    public init(size: Int, channels: Int, values: [Float]) {
        precondition(size >= 2 && channels > 0)
        precondition(values.count == size * size * channels,
                     "expected \(size * size * channels) values, got \(values.count)")
        self.size = size
        self.channels = channels
        self.values = values
    }

    /// `_cubic_interp_lut_at_2d`. `x` and `y` are already in LUT cell units
    /// (`tc * (size - 1)`).
    public func lookup(x: Float, y: Float) -> SIMD3<Float> {
        let n = size
        let (bx, fx) = ChromaTable.baseAndFraction(x, n)
        let (by, fy) = ChromaTable.baseAndFraction(y, n)

        // Four weights per axis, written out rather than kept in a SIMD4: the
        // subscript of a vector is settable, but this is the code that has to
        // compile first time on a machine we cannot reach.
        let wx0 = ChromaTable.mitchellWeight(fx + 1)
        let wx1 = ChromaTable.mitchellWeight(fx)
        let wx2 = ChromaTable.mitchellWeight(fx - 1)
        let wx3 = ChromaTable.mitchellWeight(fx - 2)
        let wy0 = ChromaTable.mitchellWeight(fy + 1)
        let wy1 = ChromaTable.mitchellWeight(fy)
        let wy2 = ChromaTable.mitchellWeight(fy - 1)
        let wy3 = ChromaTable.mitchellWeight(fy - 2)
        let wx = [wx0, wx1, wx2, wx3]
        let wy = [wy0, wy1, wy2, wy3]

        var out = SIMD3<Float>(0, 0, 0)
        var weightSum: Float = 0
        for i in 0..<4 {
            let xi = ChromaTable.reflectedIndex(bx - 1 + i, n)
            for j in 0..<4 {
                let yj = ChromaTable.reflectedIndex(by - 1 + j, n)
                let w = wx[i] * wy[j]
                weightSum += w
                let base = (xi * n + yj) * channels
                out.x += w * values[base]
                out.y += w * values[base + 1]
                out.z += w * values[base + 2]
            }
        }
        if weightSum != 0 {
            out = out / weightSum
        }
        return out
    }

    // MARK: - the reference's helpers, transcribed

    /// `clamp_coordinate` + `cubic_coordinate_base_fraction`.
    @inline(__always)
    static func baseAndFraction(_ coordinate: Float, _ n: Int) -> (Int, Float) {
        let upper = Float(n - 1)
        let c: Float = coordinate.isFinite ? min(max(coordinate, 0), upper) : 0
        if c >= upper { return (n - 2, 1) }
        let base = Int(c.rounded(.down))
        return (base, c - Float(base))
    }

    /// `safe_index`: symmetric reflection into `0…n-1`.
    @inline(__always)
    static func reflectedIndex(_ index: Int, _ n: Int) -> Int {
        if index < 0 { return -index }
        if index >= n { return 2 * (n - 1) - index }
        return index
    }

    /// `mitchell_weight` with B = C = 1/3.
    @inline(__always)
    static func mitchellWeight(_ t: Float) -> Float {
        let b: Float = 1.0 / 3.0
        let c: Float = 1.0 / 3.0
        let x = abs(t)
        if x < 1 {
            return (1.0 / 6.0) * ((12 - 9 * b - 6 * c) * x * x * x
                                  + (-18 + 12 * b + 6 * c) * x * x
                                  + (6 - 2 * b))
        }
        if x < 2 {
            return (1.0 / 6.0) * ((-b - 6 * c) * x * x * x
                                  + (6 * b + 30 * c) * x * x
                                  + (-12 * b - 48 * c) * x
                                  + (8 * b + 24 * c))
        }
        return 0
    }
}
