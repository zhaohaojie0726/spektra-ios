import Foundation

/// The sRGB transfer function (IEC 61966-2-1), in both directions.
///
/// It lives in the core rather than next to Core Graphics so the two curves are
/// the same functions the golden data was produced with — and so they can be
/// checked on a machine without a Mac.
public enum SRGB {
    @inline(__always)
    public static func decode(_ encoded: Float) -> Float {
        if encoded <= 0.04045 { return encoded / 12.92 }
        return Float(pow(Double((encoded + 0.055) / 1.055), 2.4))
    }

    @inline(__always)
    public static func encode(_ linear: Float) -> Float {
        if linear <= 0.0031308 { return 12.92 * linear }
        return 1.055 * Float(pow(Double(linear), 1.0 / 2.4)) - 0.055
    }
}
