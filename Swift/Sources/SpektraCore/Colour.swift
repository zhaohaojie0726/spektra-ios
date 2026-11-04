import Foundation

/// A 3×3 linear map from an RGB space to CIE XYZ, already chromatically
/// adapted to the film's reference illuminant.
///
/// The matrix is baked by `Reference/export_goldens.py` from colour-science:
/// `RGB_to_XYZ(eye, colourspace: input, illuminant: filmIlluminant, CAT16)`.
/// Its rows are the source space's channels, its columns the destination's, so
/// `xyz = Mᵀ · rgb` — `np.dot(rgb, M)` in the reference.
public struct ColourMatrix {
    public let row0: SIMD3<Float>
    public let row1: SIMD3<Float>
    public let row2: SIMD3<Float>

    /// `values` is row-major: `[m00, m01, m02, m10, …]`, rows = source.
    public init(rowMajor values: [Float]) {
        precondition(values.count == 9, "colour matrix needs 9 values")
        row0 = SIMD3(values[0], values[1], values[2])
        row1 = SIMD3(values[3], values[4], values[5])
        row2 = SIMD3(values[6], values[7], values[8])
    }

    @inline(__always)
    public func xyz(_ v: SIMD3<Float>) -> SIMD3<Float> {
        // out = Mᵀ · v
        SIMD3(row0.x * v.x + row1.x * v.y + row2.x * v.z,
              row0.y * v.x + row1.y * v.y + row2.y * v.z,
              row0.z * v.x + row1.z * v.y + row2.z * v.z)
    }
}

/// CIE xy chromaticity from XYZ, plus the brightness `b = X+Y+Z` the Hanatos
/// upsampling uses as its scale factor.
@inline(__always)
public func chromaticity(fromXYZ xyz: SIMD3<Float>) -> (x: Float, y: Float, b: Float) {
    let sum = xyz.x + xyz.y + xyz.z
    // numpy: xy = xyz[:2] / fmax(b, 1e-10); then b = nan_to_num(b)
    let denominator = max(sum, 1e-10)
    let b = sum.isFinite ? sum : 0
    return (xyz.x / denominator, xyz.y / denominator, b)
}

/// `_tri2quad`: maps xy chromaticity into the unit square the spectra LUT is
/// indexed by. Both outputs are clipped to 0…1, NaN maps to 0.
@inline(__always)
public func triangularToSquare(x: Float, y: Float) -> (x: Float, y: Float) {
    let s = 1 - x
    let tx = clamp01(s * s)
    let ty = clamp01(y / max(s, 1e-10))
    return (tx, ty)
}

@inline(__always)
func clamp01(_ v: Float) -> Float {
    v.isFinite ? min(max(v, 0), 1) : 0
}
