import CairnFrame
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// A rendered frame read back from the GPU: BGRA, premultiplied, rows top to bottom.
public struct Image: Sendable {
    public let width: Int, height: Int
    public let bgra: [UInt8]

    /// The pixel at (x, y) in device pixels, un-premultiplied.
    public func pixel(_ x: Int, _ y: Int) -> Color {
        precondition(x >= 0 && y >= 0 && x < width && y < height, "pixel (\(x), \(y)) outside \(width)×\(height)")
        let i = (y * width + x) * 4
        let a = bgra[i + 3]
        func un(_ v: UInt8) -> UInt8 {
            a == 0 ? 0 : UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a)))
        }
        return Color(r: un(bgra[i + 2]), g: un(bgra[i + 1]), b: un(bgra[i]), a: a)
    }

    public func cgImage() -> CGImage {
        let provider = CGDataProvider(data: Data(bgra) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    public func writePNG(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, cgImage(), nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Loads a PNG written by `writePNG` (or any image) as BGRA premultiplied.
    public static func readPNG(from url: URL) -> Image? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.setBlendMode(.copy)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Image(width: w, height: h, bgra: bytes) : nil
    }
}

extension Renderer {
    /// Renders `frame` offscreen at `scale` (the target is `frame.size × scale`, rounded up) and
    /// reads it back. Blocks until the GPU is done.
    public func image(_ frame: Frame, scale: Float = 2) throws -> Image {
        let w = max(1, Int((Float(frame.size.w) * scale).rounded(.up)))
        let h = max(1, Int((Float(frame.size.h) * scale).rounded(.up)))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { throw RenderError.textureAllocation }
        draw(frame: frame, into: tex, scale: scale).waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return Image(width: w, height: h, bgra: bytes)
    }

    /// The colour painted at a logical point: the device pixel that contains the point's centre
    /// (x + ½, y + ½), rendered at `scale`. For conformance checks such as "this control's box
    /// is painted": probe the control's centre and compare with its fill.
    public func probe(_ frame: Frame, at p: Point, scale: Float = 2) throws -> Color {
        let img = try image(frame, scale: scale)
        let x = Int(((Float(p.x) + 0.5) * scale).rounded(.down))
        let y = Int(((Float(p.y) + 0.5) * scale).rounded(.down))
        return img.pixel(min(max(x, 0), img.width - 1), min(max(y, 0), img.height - 1))
    }

    /// Several probes from one render.
    public func probe(_ frame: Frame, at points: [Point], scale: Float = 2) throws -> [Color] {
        let img = try image(frame, scale: scale)
        return points.map { p in
            let x = Int(((Float(p.x) + 0.5) * scale).rounded(.down))
            let y = Int(((Float(p.y) + 0.5) * scale).rounded(.down))
            return img.pixel(min(max(x, 0), img.width - 1), min(max(y, 0), img.height - 1))
        }
    }
}
