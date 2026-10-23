import CairnFrame
import CairnRender
import CoreGraphics
import Foundation
import ImageIO
import Metal
import QuartzCore

/// The window's renderer under the debug socket: `MetalRenderer`'s work (the same
/// `CairnRender.Renderer`, clear colour and layer setup), plus a copy of every drawable it
/// presents, so the socket can read pixels from what was actually put on screen.
///
/// After the renderer has painted the drawable, a blit copies its texture into a shared
/// texture, and only then is the drawable presented. The render thread waits for the GPU each
/// frame, which costs a little latency; it only happens under the debug socket.
final class DebugRenderer: FrameRenderer, @unchecked Sendable {
    private let renderer: Renderer
    private let queue: MTLCommandQueue
    var device: MTLDevice { renderer.device }
    let clearColor = MetalRenderer.defaultClearColor

    private let lock = NSLock()
    private var capture: MTLTexture?
    private var capturedFrame: Frame?
    private var capturedScale: CGFloat = 2

    init() {
        do { renderer = try Renderer() } catch { fatalError("cairn: no Metal renderer (\(error))") }
        renderer.clearColor = clearColor
        queue = renderer.device.makeCommandQueue()!
    }

    func configure(_ layer: CAMetalLayer) {
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false  // the blit reads the drawable
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {
        autoreleasepool {
            let source = drawable.texture
            renderer.draw(frame: frame, into: source, scale: Float(viewport.scale)).waitUntilCompleted()
            lock.lock()
            if capture?.width != source.width || capture?.height != source.height {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: source.width,
                                                                 height: source.height, mipmapped: false)
                d.storageMode = .shared
                d.usage = [.shaderRead]
                capture = device.makeTexture(descriptor: d)
            }
            let target = capture
            lock.unlock()
            guard let target, let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() else {
                drawable.present()
                return
            }
            blit.copy(from: source, to: target)
            blit.endEncoding()
            cmd.present(drawable)
            cmd.commit()
            cmd.waitUntilCompleted()
            lock.lock()
            capturedFrame = frame
            capturedScale = viewport.scale
            lock.unlock()
        }
    }

    /// The frame last put on screen.
    var lastFrame: Frame? {
        lock.lock()
        defer { lock.unlock() }
        return capturedFrame
    }

    /// Colours at logical points of the last presented drawable (the device pixel holding each
    /// point's centre), if `frame` is what it shows.
    func pixels(_ points: [Point], of frame: Frame) -> [Color]? {
        lock.lock()
        defer { lock.unlock() }
        guard let tex = capture, capturedFrame == frame else { return nil }
        return points.map { p in
            let x = min(max(Int(((CGFloat(p.x) + 0.5) * capturedScale).rounded(.down)), 0), tex.width - 1)
            let y = min(max(Int(((CGFloat(p.y) + 0.5) * capturedScale).rounded(.down)), 0), tex.height - 1)
            var px = [UInt8](repeating: 0, count: 4)
            tex.getBytes(&px, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return Color(r: px[2], g: px[1], b: px[0], a: px[3])
        }
    }

    /// Writes the last presented drawable to a PNG (for failure reports).
    func writePNG(to url: URL) -> Bool {
        lock.lock()
        guard let tex = capture else { lock.unlock(); return false }
        var bytes = [UInt8](repeating: 0, count: tex.width * tex.height * 4)
        tex.getBytes(&bytes, bytesPerRow: tex.width * 4, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        let (w, h) = (tex.width, tex.height)
        lock.unlock()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}
