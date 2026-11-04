import Foundation

/// Stage 1 of the pipeline: linear RGB -> the film's log10 exposure.
///
/// Port of `FilmingStage._rgb_to_film_raw` plus the tail of `expose`, in the
/// deterministic configuration (`debug.lut_mode = true`, no grain, no halation,
/// no auto exposure, exposure compensation 0):
///
/// ```
/// xyz  = M^T * rgb            (M = baked matrix, CAT16 to the film white)
/// b    = X + Y + Z
/// (tx, ty) = triangularToSquare(x/b, y/b)
/// raw  = chromaTable(tx*191, ty*191) * b
/// out  = log10(max(raw, 0) + 1e-10)
/// ```
public enum FilmExposure {
    public static let logEpsilon: Float = 1e-10

    /// `rgb` is tightly packed linear RGB, row-major, `width * height * 3`.
    public static func logExposure(rgb: [Float],
                                   width: Int,
                                   height: Int,
                                   matrix: ColourMatrix,
                                   table: ChromaTable) -> [Float] {
        precondition(rgb.count == width * height * 3, "pixel buffer size mismatch")
        var out = [Float](repeating: 0, count: rgb.count)
        let scale = Float(table.size - 1)

        for index in 0..<(width * height) {
            let i = index * 3
            let xyz = matrix.xyz(SIMD3(rgb[i], rgb[i + 1], rgb[i + 2]))
            let chroma = chromaticity(fromXYZ: xyz)
            let square = triangularToSquare(x: chroma.x, y: chroma.y)
            let raw = table.lookup(x: square.x * scale, y: square.y * scale) * chroma.b
            out[i] = log10F(max(raw.x, 0) + logEpsilon)
            out[i + 1] = log10F(max(raw.y, 0) + logEpsilon)
            out[i + 2] = log10F(max(raw.z, 0) + logEpsilon)
        }
        return out
    }
}
