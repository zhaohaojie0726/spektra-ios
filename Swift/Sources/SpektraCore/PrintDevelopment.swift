import Foundation

/// Stage 4: the paper's log10 exposure → the print's CMY dye densities.
///
/// `develop_print_morph` evaluates the fitted model at the 256-sample exposure
/// axis and then interpolates the image through those curves with the same
/// right-biased linear lookup stage 2 uses.
public enum PrintDevelopment {
    public static func density(logExposure: [Float],
                               width: Int,
                               height: Int,
                               exposureAxis: [Float],
                               model: DensityCurveModel,
                               positive: Bool) -> [Float] {
        precondition(logExposure.count == width * height * 3)
        let densities = model.evaluate(exposureAxis, positive: positive)
        let curves = CharacteristicCurves(exposure: exposureAxis, densities: densities)

        var out = [Float](repeating: 0, count: logExposure.count)
        for index in 0..<(width * height) {
            let i = index * 3
            let value = curves.value(SIMD3(logExposure[i], logExposure[i + 1], logExposure[i + 2]))
            out[i] = value.x
            out[i + 1] = value.y
            out[i + 2] = value.z
        }
        return out
    }
}
