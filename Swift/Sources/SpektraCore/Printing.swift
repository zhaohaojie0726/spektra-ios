import Foundation

/// The enlarger's fixed spectral furniture: the lamp's spectrum and the three
/// dichroic filter curves. The film/paper data lives in `Profile`.
public struct EnlargerSetup {
    /// 81 samples, 380...780 nm.
    public let baseIlluminant: [Float]
    /// 81 x 3 dichroic transmittances, channel-interleaved (C, M, Y).
    public let dichroicFilters: [Float]
    /// Kodak CC units of the neutral pack (~52.5, 51.6, 0 for the DB entry).
    public var ccNeutral: SIMD3<Float>

    public init(baseIlluminant: [Float], dichroicFilters: [Float], ccNeutral: SIMD3<Float>) {
        precondition(baseIlluminant.count == 81)
        precondition(dichroicFilters.count == 81 * 3)
        self.baseIlluminant = baseIlluminant
        self.dichroicFilters = dichroicFilters
        self.ccNeutral = ccNeutral
    }

    /// `DichroicFilters.apply_cc`: transmittance 10^(-CC/100), dimmed against
    /// the filter curve, multiplied across C, M and Y.
    public func filteredIlluminant(cc: SIMD3<Float>, shift: SIMD3<Float> = .zero) -> [Float] {
        let values = cc + shift
        let transmittance = SIMD3<Float>(pow10(-values.x / 100),
                                         pow10(-values.y / 100),
                                         pow10(-values.z / 100))
        var out = [Float](repeating: 0, count: 81)
        for lambda in 0..<81 {
            var total: Float = 1
            for channel in 0..<3 {
                let f = dichroicFilters[lambda * 3 + channel]
                let dimmed = 1 - (1 - f) * (1 - transmittance[channel])
                total *= dimmed
            }
            out[lambda] = baseIlluminant[lambda] * total
        }
        return out
    }
}

/// Stage 3: negative dye density -> the paper's log10 exposure.
///
/// Port of `PrintingStage.expose` with the enlarger LUT off, print exposure
/// 1.0 and no pre-flash: the negative's spectral density attenuates the
/// filtered lamp light, the paper's 81-band sensitivities integrate it, and the
/// result is normalised so an 18 % grey prints neutral.
public enum PrintingExposure {
    public static let wavelengths = 81

    /// `1 / geometric_mean(sum_lambda 10^(-density) * light * sensitivity)`.
    /// The reference averages the log of the three channels, so the factor is
    /// one scalar applied to red, green and blue alike.
    public static func midgrayFactor(midgrayDensity: [Float],
                                     filteredIlluminant: [Float],
                                     paperSensitivity: [Float]) -> Float {
        var raw = SIMD3<Float>(0, 0, 0)
        for lambda in 0..<wavelengths {
            let light = pow10(-midgrayDensity[lambda]) * filteredIlluminant[lambda]
            let g = light.isFinite ? light : 0
            raw.x += g * paperSensitivity[lambda * 3]
            raw.y += g * paperSensitivity[lambda * 3 + 1]
            raw.z += g * paperSensitivity[lambda * 3 + 2]
        }
        let r = max(raw.x, 1e-10), g = max(raw.y, 1e-10), b = max(raw.z, 1e-10)
        let geometricMean = expF((logF(r) + logF(g) + logF(b)) / 3)
        return 1 / geometricMean
    }

    /// `cmy` is the negative's densities, `width * height * 3`.
    /// `threads == 0` uses one block per active processor.
    public static func logExposure(cmy: [Float],
                                   width: Int,
                                   height: Int,
                                   filmChannelDensity: [Float],
                                   filmBaseDensity: [Float],
                                   paperSensitivity: [Float],
                                   filteredIlluminant: [Float],
                                   midgrayFactor: Float,
                                   printExposure: Float = 1,
                                   threads: Int = 0) -> [Float] {
        precondition(cmy.count == width * height * 3)
        var out = [Float](repeating: 0, count: cmy.count)
        let gain = midgrayFactor * printExposure

        out.withUnsafeMutableBufferPointer { destination in
            cmy.withUnsafeBufferPointer { source in
                Parallel.rows(height, threads: threads) { start, end in
                    for y in start..<end {
                        for x in 0..<width {
                            let i = (y * width + x) * 3
                            let density = SIMD3(source[i], source[i + 1], source[i + 2])
                            var raw = SIMD3<Float>(0, 0, 0)

                            for lambda in 0..<wavelengths {
                                let base = lambda * 3
                                let spectralDensity = density.x * filmChannelDensity[base]
                                    + density.y * filmChannelDensity[base + 1]
                                    + density.z * filmChannelDensity[base + 2]
                                    + filmBaseDensity[lambda]
                                var light = pow10(-spectralDensity) * filteredIlluminant[lambda]
                                if !light.isFinite { light = 0 }
                                raw.x += light * paperSensitivity[base]
                                raw.y += light * paperSensitivity[base + 1]
                                raw.z += light * paperSensitivity[base + 2]
                            }

                            raw = raw * gain
                            destination[i] = log10F(max(raw.x, 0) + 1e-10)
                            destination[i + 1] = log10F(max(raw.y, 0) + 1e-10)
                            destination[i + 2] = log10F(max(raw.z, 0) + 1e-10)
                        }
                    }
                }
            }
        }
        return out
    }

    /// Sensitivity is stored as log10; the integral wants linear values.
    public static func linearSensitivity(_ logSensitivity: [Float]) -> [Float] {
        logSensitivity.map { $0.isFinite ? pow10($0) : 0 }
    }
}
