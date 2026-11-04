import Foundation

/// Stage 5: the print's dye density → output RGB.
///
/// Port of `ScanningStage.scan` with the scanner LUT off, no blur / unsharp
/// mask and no glare:
///
/// ```
/// light = 10^(−D_λ) · viewingIlluminant_λ
/// XYZ   = Σ_λ light_λ · CMF_λ / normalisation
/// rgb   = M_xyz→rgb · XYZ            (adapted viewing white → output white)
/// rgb   = R · rgb                    (colour's same-space round trip)
/// out   = sRGB(rgb)                  (CCTF, if the output asks for it)
/// ```
public enum Scanning {
    public static let wavelengths = 81

    /// The scanner's fixed data: viewing illuminant, observer, and the output
    /// transform. Everything here is baked per output colour space.
    public struct Setup {
        public let viewingIlluminant: [Float]
        public let cmfs: [Float]                 // 81 × 3
        public let normalization: Float          // Σ illum · CMF_ȳ
        public let xyzToRGB: ColourMatrix
        public let roundtrip: ColourMatrix
        public let encode: Bool

        public init(viewingIlluminant: [Float], cmfs: [Float], normalization: Float,
                    xyzToRGB: ColourMatrix, roundtrip: ColourMatrix, encode: Bool) {
            self.viewingIlluminant = viewingIlluminant
            self.cmfs = cmfs
            self.normalization = normalization
            self.xyzToRGB = xyzToRGB
            self.roundtrip = roundtrip
            self.encode = encode
        }
    }
    @inline(__always)
    public static func srgbEncode(_ x: Float) -> Float {
        SRGB.encode(x)
    }

    /// Returns the output-encoded RGB (`width * height * 3`).
    /// `threads == 0` uses one block per active processor.
    public static func outputRGB(cmy: [Float],
                                 width: Int,
                                 height: Int,
                                 channelDensity: [Float],
                                 baseDensity: [Float],
                                 viewingIlluminant: [Float],
                                 cmfs: [Float],
                                 normalization: Float,
                                 xyzToRGB: ColourMatrix,
                                 roundtrip: ColourMatrix,
                                 encode: Bool,
                                 threads: Int = 0) -> [Float] {
        precondition(cmy.count == width * height * 3)
        var out = [Float](repeating: 0, count: cmy.count)
        let scale = 1 / normalization

        out.withUnsafeMutableBufferPointer { destination in
            cmy.withUnsafeBufferPointer { source in
                Parallel.rows(height, threads: threads) { start, end in
                    for y in start..<end {
                        for x in 0..<width {
                            let i = (y * width + x) * 3
                            let density = SIMD3(source[i], source[i + 1], source[i + 2])
                            var xyz = SIMD3<Float>(0, 0, 0)

                            for lambda in 0..<wavelengths {
                                let base = lambda * 3
                                let spectralDensity = density.x * channelDensity[base]
                                    + density.y * channelDensity[base + 1]
                                    + density.z * channelDensity[base + 2]
                                    + baseDensity[lambda]
                                var light = pow10(-spectralDensity) * viewingIlluminant[lambda]
                                if !light.isFinite { light = 0 }
                                xyz.x += light * cmfs[base]
                                xyz.y += light * cmfs[base + 1]
                                xyz.z += light * cmfs[base + 2]
                            }

                            xyz = xyz * scale
                            var rgb = xyzToRGB.xyz(xyz)
                            rgb = roundtrip.xyz(rgb)

                            if encode {
                                destination[i] = srgbEncode(rgb.x)
                                destination[i + 1] = srgbEncode(rgb.y)
                                destination[i + 2] = srgbEncode(rgb.z)
                            } else {
                                destination[i] = rgb.x
                                destination[i + 1] = rgb.y
                                destination[i + 2] = rgb.z
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}
