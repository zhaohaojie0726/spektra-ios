import Foundation

/// A row-major 3×3. `rows` are the first index. `apply(v)` computes
/// `out[i] = Σ_j m[j][i] * v[j]` — the convention `np.dot(v, M)` has, where the
/// coupler matrix is indexed `[donor, receiver]`: a donor's density reaches a
/// receiver through the *column*, not the row.
public struct Matrix3 {
    public let row0: SIMD3<Float>
    public let row1: SIMD3<Float>
    public let row2: SIMD3<Float>

    public init(rowMajor values: [Float]) {
        precondition(values.count == 9, "matrix needs 9 values")
        row0 = SIMD3(values[0], values[1], values[2])
        row1 = SIMD3(values[3], values[4], values[5])
        row2 = SIMD3(values[6], values[7], values[8])
    }

    @inline(__always)
    public func apply(_ v: SIMD3<Float>) -> SIMD3<Float> {
        // out = Mᵀ · v, written out: `SIMD3` has no `dot` member.
        SIMD3(row0.x * v.x + row1.x * v.y + row2.x * v.z,
              row0.y * v.x + row1.y * v.y + row2.y * v.z,
              row0.z * v.x + row1.z * v.y + row2.z * v.z)
    }
}

/// The characteristic curves of a film or paper, normalised the way `develop()`
/// normalises them: minus the per-channel minimum, so the toe sits at zero.
public struct CharacteristicCurves {
    public let exposure: [Float]     // 256 log10 exposures, increasing
    public let densities: [Float]    // 256 × 3, channel-interleaved

    public init(logExposure: [Float], densityCurves: [Float]) {
        precondition(logExposure.count > 1)
        precondition(densityCurves.count == logExposure.count * 3)

        var minima = SIMD3<Float>(.greatestFiniteMagnitude,
                                  .greatestFiniteMagnitude,
                                  .greatestFiniteMagnitude)
        for i in 0..<logExposure.count {
            for c in 0..<3 {
                let v = densityCurves[i * 3 + c]
                guard v.isFinite else { continue }
                if v < minima[c] { minima[c] = v }
            }
        }
        exposure = logExposure
        densities = densityCurves.enumerated().map { index, value in
            value - minima[index % 3]
        }
    }

    /// Already-normalised curves, used for the coupler back-solve.
    init(exposure: [Float], densities: [Float]) {
        self.exposure = exposure
        self.densities = densities
    }

    /// `fast_interp`: linear, right-biased at ties, clamped outside the axis.
    @inline(__always)
    public func value(_ x: Float, channel: Int) -> Float {
        let n = exposure.count
        if !x.isFinite { return x }
        if x <= exposure[0] { return densities[channel] }
        if x >= exposure[n - 1] { return densities[(n - 1) * 3 + channel] }

        var lo = 0, hi = n - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if exposure[mid] > x { hi = mid } else { lo = mid + 1 }
        }
        let j = max(lo, 1)
        let i = j - 1
        let dx = exposure[j] - exposure[i]
        let t = dx != 0 ? (x - exposure[i]) / dx : 0
        let y0 = densities[i * 3 + channel]
        let y1 = densities[j * 3 + channel]
        return y0 + t * (y1 - y0)
    }

    @inline(__always)
    public func value(_ logExposure: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(value(logExposure.x, channel: 0),
              value(logExposure.y, channel: 1),
              value(logExposure.z, channel: 2))
    }

    /// `np.interp` on a possibly non-monotonic axis: the back-solve step that
    /// removes the couplers' effect from the published curves.
    public static func numpyInterp(x: [Float], xp: [Float], fp: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        let n = xp.count
        for k in 0..<x.count {
            let v = x[k]
            if !v.isFinite { out[k] = v; continue }
            if v <= xp[0] { out[k] = fp[0]; continue }
            if v >= xp[n - 1] { out[k] = fp[n - 1]; continue }
            var lo = 0, hi = n - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if xp[mid] >= v { hi = mid } else { lo = mid + 1 }
            }
            let j = max(lo, 1)
            let i = j - 1
            let dx = xp[j] - xp[i]
            let slope = dx != 0 ? (fp[j] - fp[i]) / dx : 0
            out[k] = slope * (v - xp[i]) + fp[i]
        }
        return out
    }
}
