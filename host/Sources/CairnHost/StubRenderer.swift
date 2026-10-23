import AppKit
import CairnFrame
import CoreGraphics
import CoreText
import Metal
import QuartzCore

/// A stand-in for the Metal renderer (workstream F, `CairnRender`): it paints every `Draw` with
/// Core Graphics into a bitmap and copies it into the drawable. Correct but not fast (about a
/// millisecond for a small window at 2x); it exists so the host can be run and checked by eye
/// before F lands. Swap it out by passing F's renderer to `CairnApp.run`.
public final class StubRenderer: FrameRenderer {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private var texture: MTLTexture?
    private var context: CGContext?

    public init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
    }

    public func configure(_ layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false  // the blit writes into the drawable
    }

    public func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {
        let w = drawable.texture.width, h = drawable.texture.height
        if context?.width != w || context?.height != h {
            context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.storageMode = .shared
            texture = device.makeTexture(descriptor: d)
        }
        guard let ctx = context, let texture else { return }
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Logical points, y down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: viewport.scale, y: -viewport.scale)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        Self.paint(frame.draws, in: ctx)
        ctx.restoreGState()

        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: ctx.data!, bytesPerRow: w * 4)
        let cmd = queue.makeCommandBuffer()!
        let blit = cmd.makeBlitCommandEncoder()!
        blit.copy(from: texture, to: drawable.texture)
        blit.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    static func paint(_ draws: [Draw], in ctx: CGContext) {
        var depth = 0
        for d in draws {
            switch d {
            case let .rect(r, fill, radius, border):
                let rect = r.cg
                let rad = min(CGFloat(radius), rect.width / 2, rect.height / 2)
                if let fill {
                    ctx.setFillColor(fill.cg)
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rad, cornerHeight: rad, transform: nil))
                    ctx.fillPath()
                }
                if let border, border.width > 0 {
                    let bw = CGFloat(border.width)
                    let inset = rect.insetBy(dx: bw / 2, dy: bw / 2)
                    let ir = max(0, rad - bw / 2)
                    ctx.setStrokeColor(border.color.cg)
                    ctx.setLineWidth(bw)
                    ctx.addPath(CGPath(roundedRect: inset, cornerWidth: ir, cornerHeight: ir, transform: nil))
                    ctx.strokePath()
                }
            case let .text(origin, font, color, string):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font.ctFont, .foregroundColor: color.cg,
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
                ctx.textPosition = CGPoint(x: CGFloat(origin.x), y: CGFloat(origin.y))
                CTLineDraw(line, ctx)
            case let .pushClip(r):
                ctx.saveGState()
                depth += 1
                ctx.clip(to: r.cg)
            case .popClip:
                if depth > 0 { ctx.restoreGState(); depth -= 1 }
            }
        }
        while depth > 0 { ctx.restoreGState(); depth -= 1 }
    }
}

extension Rect { var cg: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h)) } }
extension Color {
    var cg: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255) }
}

extension Font {
    /// The Core Text font for a frame `Font`. Family 0 is the system UI font, 1 the system
    /// monospaced font. (F's `CairnRender` owns the canonical mapping and the metrics Lean sees;
    /// this one is for the stub renderer and `characterIndex(for:)`.)
    var ctFont: CTFont {
        let weights: [(UInt32, CGFloat)] = [(100, -0.8), (200, -0.6), (300, -0.4), (400, 0), (500, 0.23),
                                            (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62)]
        let wt = weights.min { abs(Int($0.0) - Int(weight)) < abs(Int($1.0) - Int(weight)) }!.1
        let base: CTFont = family == 1
            ? NSFontShim.monospaced(size: CGFloat(size), weight: wt)
            : NSFontShim.system(size: CGFloat(size), weight: wt)
        guard italic else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .traitItalic, .traitItalic) ?? base
    }
}

enum NSFontShim {
    static func system(size: CGFloat, weight: CGFloat) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: NSFont.Weight(weight)) as CTFont
    }
    static func monospaced(size: CGFloat, weight: CGFloat) -> CTFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: NSFont.Weight(weight)) as CTFont
    }
}
