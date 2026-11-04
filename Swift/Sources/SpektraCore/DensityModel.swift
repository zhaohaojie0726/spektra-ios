import Foundation

/// The fitted characteristic curve of a stock: three layers per channel, each a
/// normal CDF, summed with its amplitude.
///
/// The stored 256-sample `density_curves` array is only a sampling of this
/// model and differs from it by ~3e-3, which is visible in a print — the
/// reference always evaluates the model (`_evaluate_fitted_density`).
public struct DensityCurveModel {
    public let modelType: String
    /// `[channel][layer]`
    public let centers: [[Float]]
    public let amplitudes: [[Float]]
    public let sigmas: [[Float]]

    public var channelCount: Int { centers.count }
    public var layersPerChannel: Int { centers.first?.count ?? 0 }

    public init(modelType: String,
                centers: [[Float]],
                amplitudes: [[Float]],
                sigmas: [[Float]]) {
        self.modelType = modelType
        self.centers = centers
        self.amplitudes = amplitudes
        self.sigmas = sigmas
    }

    /// Parses `data.density_curves_model`; returns nil when absent.
    public static func parse(_ value: Any?) -> DensityCurveModel? {
        guard let dict = value as? [String: Any],
              let centers = knots(dict["centers"]),
              let amplitudes = knots(dict["amplitudes"]),
              let sigmas = knots(dict["sigmas"])
        else { return nil }
        return DensityCurveModel(modelType: dict["model_type"] as? String ?? "cdfs",
                                 centers: centers,
                                 amplitudes: amplitudes,
                                 sigmas: sigmas)
    }

    private static func knots(_ value: Any?) -> [[Float]]? {
        guard let rows = value as? [Any] else { return nil }
        var out: [[Float]] = []
        for row in rows {
            guard let values = row as? [NSNumber] else { return nil }
            out.append(values.map { $0.floatValue })
        }
        return out
    }

    /// `_evaluate_fitted_density` for one channel.
    public func evaluate(_ x: Float, channel: Int, positive: Bool) -> Float {
        var total: Float = 0
        for layer in 0..<layersPerChannel {
            let z = (x - centers[channel][layer]) / sigmas[channel][layer]
            total += amplitudes[channel][layer] * DensityCurveModel.normalCDF(z, positive: positive)
        }
        return total
    }

    /// Evaluates every channel on a common exposure axis: `axis.count × 3`,
    /// channel-interleaved.
    public func evaluate(_ axis: [Float], positive: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: axis.count * 3)
        for i in 0..<axis.count {
            for c in 0..<3 {
                out[i * 3 + c] = evaluate(axis[i], channel: c, positive: positive)
            }
        }
        return out
    }

    @inline(__always)
    static func normalCDF(_ z: Float, positive: Bool) -> Float {
        let signed = positive ? -z : z
        return Float(0.5 * (1.0 + erf(Double(signed) / 2.0.squareRoot())))
    }
}
