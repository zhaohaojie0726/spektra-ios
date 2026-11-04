import Foundation

/// Float math through the Double implementations.
///
/// The C math functions have Float overloads on Apple platforms, but their
/// availability varies by SDK and by module (`Darwin` vs `Foundation`), and a
/// missing overload is a compile error that reads like a type mismatch. Going
/// through Double is exact enough here — the tolerance is 2e-5 — and removes
/// the question entirely.
@inline(__always) func expF(_ x: Float) -> Float { Float(exp(Double(x))) }
@inline(__always) func logF(_ x: Float) -> Float { Float(log(Double(x))) }
@inline(__always) func log10F(_ x: Float) -> Float { Float(log10(Double(x))) }
@inline(__always) func powF(_ x: Float, _ y: Float) -> Float { Float(pow(Double(x), Double(y))) }
@inline(__always) func sqrtF(_ x: Float) -> Float { Float(Double(x).squareRoot()) }

/// `10^x` as a single `exp2`, in Float. The two spectral integrals call this
/// once per wavelength per pixel — 162 times a pixel — so going through Double
/// `exp` here is the difference between a second and a minute on a phone.
@inline(__always) func pow10(_ x: Float) -> Float { exp2(x * 3.321_928_092_809_411_5) }
