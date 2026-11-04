import Foundation

/// DIR coupler parameters, with the reference's defaults
/// (`runtime/params_schema.py::DirCouplersParams`).
public struct DirCouplerParams {
    public var active = true
    public var amount: Float = 1
    public var inhibitionSameLayer: Float = 1
    public var inhibitionInterLayer: Float = 1
    public var gammaSameLayerRGB: SIMD3<Float> = SIMD3(0.336, 0.319, 0.273)
    public var gammaInterLayerRtoGB: SIMD2<Float> = SIMD2(0.353, 0.302)
    public var gammaInterLayerGtoRB: SIMD2<Float> = SIMD2(0.154, 0.353)
    public var gammaInterLayerBtoRG: SIMD2<Float> = SIMD2(0.168, 0.226)

    public init() {}

    /// `compute_dir_couplers_matrix` × `amount`. Row = donor layer, column =
    /// receiver layer.
    public func matrix() -> Matrix3 {
        let selfTerm = gammaSameLayerRGB * inhibitionSameLayer
        var inter = [Float](repeating: 0, count: 9)
        inter[0 * 3 + 1] = gammaInterLayerRtoGB.x
        inter[0 * 3 + 2] = gammaInterLayerRtoGB.y
        inter[1 * 3 + 0] = gammaInterLayerGtoRB.x
        inter[1 * 3 + 2] = gammaInterLayerGtoRB.y
        inter[2 * 3 + 0] = gammaInterLayerBtoRG.x
        inter[2 * 3 + 1] = gammaInterLayerBtoRG.y

        var m = [Float](repeating: 0, count: 9)
        for i in 0..<9 { m[i] = inter[i] * inhibitionInterLayer }
        m[0] += selfTerm.x
        m[4] += selfTerm.y
        m[8] += selfTerm.z
        return Matrix3(rowMajor: m.map { $0 * amount })
    }
}

/// Stage 2: log10 exposure → CMY dye densities on the negative.
///
/// Port of `develop()` for a negative film with grain and diffusion off:
///
/// ```
/// curves   = published curves − per-channel min      (done in CharacteristicCurves)
/// density  = curves(logE)
/// curves0  = back-solve the couplers out of the curves
/// logE0    = logE − M · density
/// out      = curves0(logE0)
/// ```
public enum FilmDevelopment {
    public static func density(logExposure: [Float],
                               width: Int,
                               height: Int,
                               curves: CharacteristicCurves,
                               couplers: Matrix3) -> [Float] {
        precondition(logExposure.count == width * height * 3, "pixel buffer size mismatch")
        let n = curves.exposure.count

        // 1. curves with the couplers' contrast removed (once, not per pixel)
        var shifted = [Float](repeating: 0, count: n * 3)
        for k in 0..<n {
            let d = SIMD3(curves.densities[k * 3],
                          curves.densities[k * 3 + 1],
                          curves.densities[k * 3 + 2])
            let correction = couplers.apply(d)
            shifted[k * 3] = curves.exposure[k] - correction.x
            shifted[k * 3 + 1] = curves.exposure[k] - correction.y
            shifted[k * 3 + 2] = curves.exposure[k] - correction.z
        }

        var baseDensities = [Float](repeating: 0, count: n * 3)
        for channel in 0..<3 {
            var xp = [Float](repeating: 0, count: n)
            var fp = [Float](repeating: 0, count: n)
            for k in 0..<n {
                xp[k] = shifted[k * 3 + channel]
                fp[k] = curves.densities[k * 3 + channel]
            }
            let corrected = CharacteristicCurves.numpyInterp(x: curves.exposure, xp: xp, fp: fp)
            for k in 0..<n { baseDensities[k * 3 + channel] = corrected[k] }
        }
        let baseCurves = CharacteristicCurves(exposure: curves.exposure, densities: baseDensities)

        // 2. per pixel
        var out = [Float](repeating: 0, count: logExposure.count)
        for index in 0..<(width * height) {
            let i = index * 3
            let logE = SIMD3(logExposure[i], logExposure[i + 1], logExposure[i + 2])
            let density = curves.value(logE)
            let corrected = logE - couplers.apply(density)
            let result = baseCurves.value(corrected)
            out[i] = result.x
            out[i + 1] = result.y
            out[i + 2] = result.z
        }
        return out
    }
}
