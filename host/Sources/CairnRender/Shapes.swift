import CairnFrame
import CoreGraphics
import Foundation
import Accelerate
import Metal

/// `shape` draws: a rounded rect with circular or continuous corners, an optional fill, an
/// inside border and an optional drop shadow, rasterised by Core Graphics and drawn as a texture.
///
/// The SDF rect shader draws circular corners only and has no blur, so shapes go through Core
/// Graphics, which antialiases, strokes and blurs the way AppKit and SwiftUI do. A shape whose
/// sides are long enough is drawn as nine slices of one cached texture: its four corners at
/// their own size, and one row and one column of pixels (far enough from every corner and the
/// shadow's reach that every pixel along them is the same) stretched over the edges and the
/// middle. Resizing such a shape (a panel growing as text arrives) re-uses the texture. Smaller
/// shapes are rasterised at their exact size and cached by it.
final class ShapeCache {
    struct Key: Hashable {
        var fill: Color?
        var radius: UInt32
        var border: Border?
        var corner: Corner
        var shadow: Shadow?
        var scale: Float
        /// The shape's size in device pixels when it is drawn whole; nil for a sliced texture.
        var size: SIMD2<Int32>?
    }

    /// A texture holding the shape at `core` pixels with `pad` pixels of room on every side.
    struct Entry {
        let texture: MTLTexture
        let pad: Int
        let core: SIMD2<Int>
        /// Pixels from the shape's edge to the stretched row and column (sliced entries only).
        let reach: Int
        let sliced: Bool
    }

    static let capacity = 64
    private let device: MTLDevice
    private var entries: [Key: Entry] = [:]
    private(set) var rasterised = 0

    init(device: MTLDevice) { self.device = device }

    /// Device-pixel geometry of a shape: the corner radius, the border width (the rect shader's
    /// rule: rounded half down, at least 1 px), the shadow's blur and offset.
    struct Geometry {
        /// `blur` is the shadow's Gaussian standard deviation.
        var radius: CGFloat, border: CGFloat, blur: CGFloat, dx: CGFloat, dy: CGFloat
        /// Room around the shape the shadow can reach.
        var pad: Int { shadowPad }
        var shadowPad = 0
        /// How far from an edge the corner's curve reaches.
        var cornerReach = 0
    }

    /// SwiftUI's `shadow(radius:)` as a Gaussian's standard deviation in device pixels: about the
    /// radius, fitted to the original Yap's overlay on screen (σ = 1.05 r; yap-cairn's docs/yap.md, "Overlay
    /// parity"). SwiftUI's blur is not exactly Gaussian: against its `ImageRenderer` this is
    /// within a level or two along edges and up to 7 near corners (ShapeTests.shadowsAreSwiftUIs).
    static func blur(radius: UInt32, scale: CGFloat) -> CGFloat { 1.05 * CGFloat(radius) * scale }

    static func geometry(radius: UInt32, border: Border?, corner: Corner, shadow: Shadow?, scale: Float) -> Geometry {
        let s = CGFloat(scale)
        var g = Geometry(radius: CGFloat(radius) * s,
                         border: border.map { $0.width == 0 ? 0 : max(1, CGFloat(Renderer.edgeLength($0.width, scale))) } ?? 0,
                         blur: shadow.map { blur(radius: $0.radius, scale: s) } ?? 0,
                         dx: shadow.map { CGFloat($0.x) * s } ?? 0, dy: shadow.map { CGFloat($0.y) * s } ?? 0)
        if shadow != nil { g.shadowPad = Int((3 * g.blur + abs(g.dx) + abs(g.dy)).rounded(.up)) + 2 }
        g.cornerReach = Int((g.radius * (corner == .continuous ? ContinuousCorners.extent : 1)).rounded(.up)) + 1
        return g
    }

    /// The texture for a shape `w`×`h` device pixels big.
    func entry(fill: Color?, radius: UInt32, border: Border?, corner: Corner, shadow: Shadow?,
               scale: Float, w: Int, h: Int) -> Entry? {
        let g = Self.geometry(radius: radius, border: border, corner: corner, shadow: shadow, scale: scale)
        // A stretched row or column must be beyond every corner's curve and the blur's reach.
        let reach = g.cornerReach + g.pad
        let minSide = 2 * reach + 1
        let sliced = w >= minSide && h >= minSide
        let key = Key(fill: fill, radius: radius, border: border, corner: corner, shadow: shadow, scale: scale,
                      size: sliced ? nil : SIMD2(Int32(clamping: w), Int32(clamping: h)))
        if let e = entries[key] { return e }
        let cw = sliced ? minSide : w, ch = sliced ? minSide : h
        let tw = cw + 2 * g.pad, th = ch + 2 * g.pad
        guard tw > 0, th > 0, tw <= 16384, th <= 16384,
              let tex = Self.rasterise(device: device, w: cw, h: ch, g: g, fill: fill, border: border,
                                       corner: corner, shadow: shadow)
        else { return nil }
        if entries.count >= Self.capacity { entries.removeAll(keepingCapacity: true) }
        let e = Entry(texture: tex, pad: g.pad, core: SIMD2(cw, ch), reach: reach, sliced: sliced)
        entries[key] = e
        rasterised += 1
        return e
    }

    /// The quads that draw `e` over the shape at `px`: one, or nine slices. Each is a target
    /// rect in device pixels and a texel rect in the texture.
    static func quads(_ e: Entry, _ px: PixelRect) -> [(rect: SIMD4<Float>, uv: SIMD4<Float>)] {
        let p = e.pad
        let x0 = px.x0 - p, y0 = px.y0 - p
        let tw = e.core.x + 2 * p, th = e.core.y + 2 * p
        guard e.sliced else {
            return [(SIMD4(Float(x0), Float(y0), Float(tw), Float(th)), SIMD4(0, 0, Float(tw), Float(th)))]
        }
        // Columns: [0, p + reach) at its size, one texel stretched, the rest at its size.
        let W = px.x1 - px.x0 + 2 * p, H = px.y1 - px.y0 + 2 * p
        let a = p + e.reach
        let cols: [(Int, Int, Int, Int)] = [(0, a, 0, a), (a, a + 1, a, W - (tw - a - 1)), (a + 1, tw, W - (tw - a - 1), W)]
        let rows: [(Int, Int, Int, Int)] = [(0, a, 0, a), (a, a + 1, a, H - (th - a - 1)), (a + 1, th, H - (th - a - 1), H)]
        var out: [(SIMD4<Float>, SIMD4<Float>)] = []
        for r in rows where r.3 > r.2 {
            for c in cols where c.3 > c.2 {
                out.append((SIMD4(Float(x0 + c.2), Float(y0 + r.2), Float(c.3 - c.2), Float(r.3 - r.2)),
                            SIMD4(Float(c.0), Float(r.0), Float(c.1), Float(r.1))))
            }
        }
        return out
    }

    /// The shape at `w`×`h` pixels, `g.pad` pixels in from every side of a BGRA premultiplied
    /// texture (sRGB-encoded, like every other colour in a frame).
    static func rasterise(device: MTLDevice, w: Int, h: Int, g: Geometry, fill: Color?, border: Border?,
                          corner: Corner, shadow: Shadow?) -> MTLTexture? {
        let tw = w + 2 * g.pad, th = h + 2 * g.pad
        var bytes = [UInt8](repeating: 0, count: tw * th * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: tw, height: th, bitsPerComponent: 8,
                                      bytesPerRow: tw * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            // y down, like the frame. Shadow offsets are in the base space (y up), so dy flips.
            ctx.translateBy(x: 0, y: CGFloat(th))
            ctx.scaleBy(x: 1, y: -1)
            let rect = CGRect(x: g.pad, y: g.pad, width: w, height: h)
            func cg(_ c: Color) -> CGColor {
                CGColor(colorSpace: space, components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255,
                                                        CGFloat(c.b) / 255, CGFloat(c.a) / 255])!
            }
            if let fill {
                if let shadow, g.blur > 0 || g.dx != 0 || g.dy != 0 {
                    ctx.flush()
                    Self.paintShadow(into: buf, tw: tw, th: th, g: g, shape: path(rect, radius: g.radius, corner: corner),
                                     color: shadow.color)
                }
                ctx.addPath(path(rect, radius: g.radius, corner: corner))
                ctx.setFillColor(cg(fill))
                ctx.fillPath()
            }
            if let border, g.border > 0 {
                // Inside the shape, as SwiftUI's strokeBorder: the outline inset by half the width.
                let half = g.border / 2
                ctx.addPath(path(rect.insetBy(dx: half, dy: half), radius: max(0, g.radius - half), corner: corner))
                ctx.setStrokeColor(cg(border.color))
                ctx.setLineWidth(g.border)
                ctx.strokePath()
            }
            return true
        }
        guard ok else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, tw, th), mipmapLevel: 0, withBytes: bytes, bytesPerRow: tw * 4)
        return t
    }

    /// The shape's silhouette, moved by the offset, blurred with a Gaussian of standard
    /// deviation `g.blur` (two separable passes, zero outside the texture), in `color`, written
    /// premultiplied BGRA into `buf` (which holds nothing yet).
    static func paintShadow(into buf: UnsafeMutableRawBufferPointer, tw: Int, th: Int, g: Geometry, shape: CGPath,
                            color: Color) {
        var mask = [Float](repeating: 0, count: tw * th)
        var bytes = [UInt8](repeating: 0, count: tw * th)
        bytes.withUnsafeMutableBytes { m in
            guard let ctx = CGContext(data: m.baseAddress, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return }
            ctx.translateBy(x: g.dx, y: CGFloat(th) - g.dy)
            ctx.scaleBy(x: 1, y: -1)
            ctx.addPath(shape)
            ctx.fillPath()
        }
        for i in 0..<(tw * th) { mask[i] = Float(bytes[i]) / 255 }
        if g.blur > 0 {
            let n = Int((3 * g.blur).rounded(.up))
            var k = (-n...n).map { Float(exp(-Double($0 * $0) / (2 * Double(g.blur * g.blur)))) }
            let sum = k.reduce(0, +)
            k = k.map { $0 / sum }
            var out = [Float](repeating: 0, count: tw * th)
            mask.withUnsafeMutableBytes { src in
                out.withUnsafeMutableBytes { dst in
                    var s = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(th), width: vImagePixelCount(tw), rowBytes: tw * 4)
                    var d = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(th), width: vImagePixelCount(tw), rowBytes: tw * 4)
                    _ = vImageSepConvolve_PlanarF(&s, &d, nil, 0, 0, k, UInt32(k.count), k, UInt32(k.count), 0, 0,
                                                  vImage_Flags(kvImageBackgroundColorFill))
                }
            }
            mask = out
        }
        let a = Float(color.a) / 255
        let px = buf.bindMemory(to: UInt8.self)
        for i in 0..<(tw * th) {
            let v = min(1, max(0, mask[i])) * a
            px[i * 4 + 0] = UInt8((Float(color.b) * v).rounded())
            px[i * 4 + 1] = UInt8((Float(color.g) * v).rounded())
            px[i * 4 + 2] = UInt8((Float(color.r) * v).rounded())
            px[i * 4 + 3] = UInt8((255 * v).rounded())
        }
    }

    static func path(_ r: CGRect, radius: CGFloat, corner: Corner) -> CGPath {
        let radius = max(0, min(radius, min(r.width, r.height) / 2))
        switch corner {
        case .circular:
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .continuous:
            return ContinuousCorners.path(r, radius: radius)
        }
    }
}

/// Continuous ("squircle") corners: the curve SwiftUI's `RoundedRectangle(style: .continuous)`
/// draws, point for point (checked against SwiftUI in host/Tests/CairnRenderTests). Each corner
/// is three cubic Béziers reaching `extent`·r along each edge; on a side too short for that, the
/// end point stops at the side's middle and its two nearer control points move in proportion.
enum ContinuousCorners {
    static let extent: CGFloat = 1.52866483
    // One corner, along the edge then round it, in units of the radius (SwiftUI's constants).
    static let c1: CGFloat = 1.08849323, c2: CGFloat = 0.86840689
    static let a: CGFloat = 0.63149399, b: CGFloat = 0.07491139
    static let d: CGFloat = 0.37282383, e: CGFloat = 0.16905956
    /// How far the two control points move per point the end point is pulled in.
    static let k1: CGFloat = 0.243047, k2: CGFloat = 0.091565

    static func path(_ rect: CGRect, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let w = rect.width, h = rect.height
        guard r > 0 else { p.addRect(rect); return p }
        // Along x (top and bottom edges) and along y (left and right edges).
        let ex = min(extent * r, w / 2), ey = min(extent * r, h / 2)
        let dx = extent * r - ex, dy = extent * r - ey
        let x1 = c1 * r - k1 * dx, x2 = c2 * r - k2 * dx
        let y1 = c1 * r - k1 * dy, y2 = c2 * r - k2 * dy
        // Points in a corner frame: u along the edge leaving the corner horizontally, v vertically,
        // both measured from the corner. `pt` maps them to each corner of the rect.
        func corner(_ cx: CGFloat, _ cy: CGFloat, _ sx: CGFloat, _ sy: CGFloat, first: Bool) {
            func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: rect.minX + cx + sx * u, y: rect.minY + cy + sy * v) }
            // From the vertical edge (v = ey) round to the horizontal edge (u = ex).
            if first { p.move(to: pt(0, ey)) } else { p.addLine(to: pt(0, ey)) }
            p.addCurve(to: pt(b * r, a * r), control1: pt(0, y1), control2: pt(0, y2))
            p.addCurve(to: pt(a * r, b * r), control1: pt(e * r, d * r), control2: pt(d * r, e * r))
            p.addCurve(to: pt(ex, 0), control1: pt(x2, 0), control2: pt(x1, 0))
        }
        // Clockwise in y-down space from the top-left corner's left edge.
        corner(0, 0, 1, 1, first: true)
        p.addLine(to: CGPoint(x: rect.maxX - ex, y: rect.minY))
        // Top-right: mirror u; start from the horizontal edge, so walk the corner backwards.
        func cornerReversed(_ cx: CGFloat, _ cy: CGFloat, _ sx: CGFloat, _ sy: CGFloat) {
            func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: rect.minX + cx + sx * u, y: rect.minY + cy + sy * v) }
            p.addCurve(to: pt(a * r, b * r), control1: pt(x1, 0), control2: pt(x2, 0))
            p.addCurve(to: pt(b * r, a * r), control1: pt(d * r, e * r), control2: pt(e * r, d * r))
            p.addCurve(to: pt(0, ey), control1: pt(0, y2), control2: pt(0, y1))
        }
        cornerReversed(w, 0, -1, 1)
        corner(w, h, -1, -1, first: false)
        p.addLine(to: CGPoint(x: rect.minX + ex, y: rect.maxY))
        cornerReversed(0, h, 1, -1)
        p.closeSubpath()
        return p
    }
}
