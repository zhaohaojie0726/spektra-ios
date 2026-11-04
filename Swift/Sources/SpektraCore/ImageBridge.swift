import CoreGraphics
import Foundation
import ImageIO

/// Conversion between a `CGImage` and the tightly packed linear RGB the core
/// renders.
///
/// A photo decodes into **linear Display P3** (the sRGB transfer function, P3
/// primaries; the pack's input matrix is baked for them). Sixteen bits per
/// channel, because the film curve steepens the toe and 8-bit quantisation
/// there is visible as steps in the shadows.
public enum ImageBridge {
    public struct LinearImage {
        public let pixels: [Float]
        public let width: Int
        public let height: Int
    }

    /// Decodes image data into a `CGImage`, applying the file's EXIF
    /// orientation and downsampling so the long edge is at most `maxEdge`
    /// (0 keeps the original size).
    ///
    /// Both jobs come from one call: `kCGImageSourceCreateThumbnailWithTransform`
    /// rotates to the displayed orientation — without it a portrait photo
    /// renders on its side, because `CGImageSourceCreateImageAtIndex` returns
    /// the stored pixels — and `ThumbnailMaxPixelSize` does the downsampling in
    /// the system's own resampler.
    public static func decode(data: Data, maxEdge: Int = 0) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        var longEdge = maxEdge
        if longEdge <= 0 {
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                longEdge = max(width, height)
            } else {
                longEdge = 12_000
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Decodes and linearises in one call — what the app uses.
    public static func linearRGB(from data: Data, maxEdge: Int = 0) -> LinearImage? {
        guard let image = decode(data: data, maxEdge: maxEdge) else { return nil }
        return linearRGB(from: image)
    }

    /// Decodes `cgImage`, downsampling so its long edge is at most `maxEdge`
    /// (0 keeps the original size). The downsampling is Core Graphics' — drawing
    /// straight into a smaller context — which is both better than a box filter
    /// and avoids allocating a full-resolution float buffer.
    public static func linearRGB(from cgImage: CGImage, maxEdge: Int = 0) -> LinearImage? {
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        var width = sourceWidth
        var height = sourceHeight
        if maxEdge > 0 {
            let longEdge = max(sourceWidth, sourceHeight)
            if longEdge > maxEdge {
                let scale = Double(maxEdge) / Double(longEdge)
                width = max(1, Int(Double(sourceWidth) * scale))
                height = max(1, Int(Double(sourceHeight) * scale))
            }
        }

        let bytesPerRow = width * 8   // RGBA, 16 bits per component
        // Display P3, not sRGB: an iPhone photo is usually P3, and drawing it
        // into sRGB would clip saturated colour *before* the film simulation
        // ever sees it. The transfer function is sRGB's, so `SRGB.decode`
        // stays correct; only the primaries differ, and the pack's input matrix
        // is baked for them.
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        // A nil `data` lets Core Graphics own the backing store; `context.data`
        // then points at it. Simpler and safer than allocating by hand.
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 16,
                                      bytesPerRow: bytesPerRow,
                                      space: space,
                                      bitmapInfo: bitmapInfo),
              let buffer = context.data
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let samples = buffer.bindMemory(to: UInt16.self, capacity: width * height * 4)
        var pixels = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            for c in 0..<3 {
                let encoded = Float(samples[i * 4 + c]) / 65535
                pixels[i * 3 + c] = SRGB.decode(encoded)
            }
        }
        return LinearImage(pixels: pixels, width: width, height: height)
    }

    /// Encodes the pipeline's sRGB-encoded RGB into a 16-bit `CGImage` tagged
    /// sRGB.
    public static func makeImage(fromRGB rgb: [Float], width: Int, height: Int) -> CGImage? {
        guard rgb.count == width * height * 3 else { return nil }
        var samples = [UInt16](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            for c in 0..<3 {
                let value = min(max(rgb[i * 3 + c], 0), 1)
                samples[i * 4 + c] = UInt16((value * 65535).rounded())
            }
            samples[i * 4 + 3] = 65535
        }
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<UInt16>.stride)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 16,
                       bitsPerPixel: 64,
                       bytesPerRow: width * 8,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                                | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}
