import CairnFrame
import CairnRender
import CoreGraphics
import Metal
import QuartzCore

/// The host's `FrameRenderer` over workstream F's `CairnRender.Renderer`.
public final class MetalRenderer: FrameRenderer {
    private let renderer: Renderer
    public var device: MTLDevice { renderer.device }

    /// The window background behind every frame.
    public static let defaultClearColor = Color(r: 247, g: 247, b: 245, a: 255)

    public init(clearColor: Color = MetalRenderer.defaultClearColor) {
        do { renderer = try Renderer() } catch { fatalError("cairn: no Metal renderer (\(error))") }
        renderer.clearColor = clearColor
    }

    public func configure(_ layer: CAMetalLayer) {
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        // Frame colours are sRGB bytes, blended in gamma space (docs/render.md).
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    public func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {
        renderer.draw(frame: frame, into: drawable, scale: Float(viewport.scale))
    }
}

extension Rect { var cg: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h)) } }
