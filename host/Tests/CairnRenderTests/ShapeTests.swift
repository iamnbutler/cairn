import CairnFrame
@testable import CairnRender
import CoreGraphics
import Foundation
import Metal
import SwiftUI
import Testing

/// `shape` draws: continuous corners are SwiftUI's, sliced textures equal whole ones, shadows
/// fall outside the rect, and an unregistered painter paints nothing.
@Suite struct ShapeTests {
    static func points(_ p: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        p.applyWithBlock { e in
            let n: Int
            switch e.pointee.type {
            // Curves only: SwiftUI starts mid-side, which is on a straight edge.
            case .addCurveToPoint: n = 3
            default: n = 0
            }
            for i in 0..<n { out.append(e.pointee.points[i]) }
        }
        return out
    }

    /// The same outline as `RoundedRectangle(style: .continuous)`, as a set of points (the start
    /// point and direction differ), for long sides, short sides and squares.
    @Test func continuousCornersAreSwiftUIs() {
        for (w, h, r) in [(520.0, 200.0, 14.0), (40.0, 100.0, 14.0), (30.0, 30.0, 14.0), (100.0, 37.0, 12.0), (7.0, 7.0, 3.5)] {
            let rect = CGRect(x: 3, y: 5, width: w, height: h)
            let ours = Self.points(ContinuousCorners.path(rect, radius: r))
            let theirs = Self.points(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect).cgPath)
            for p in theirs {
                let d = ours.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .infinity
                #expect(d < 0.01, "\(w)×\(h) r\(r): SwiftUI's \(p) is \(d) from our nearest point")
            }
            for p in ours {
                let d = theirs.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .infinity
                #expect(d < 0.01, "\(w)×\(h) r\(r): our \(p) is \(d) from SwiftUI's nearest point")
            }
        }
    }

    /// A shape drawn from nine slices of the cached texture is the shape drawn whole at its size,
    /// to within one level.
    @Test func slicedEqualsWhole() throws {
        let fill = rgb(0x000000), edge = Border(width: 1, color: Color(r: 43, g: 43, b: 43))
        let shadow = Shadow(color: Color(r: 0, g: 0, b: 0, a: 89), radius: 14, x: 0, y: 4)
        for (w, h) in [(520, 140), (300, 213), (180, 180)] {
            let d = Draw.shape(R(18, 18, Int32(w), Int32(h)), fill: fill, radius: 14, border: edge,
                               corner: .continuous, shadow: shadow)
            let f = frame(Int32(w) + 36, Int32(h) + 36, [d])
            let sliced = try withRenderer { r -> CairnRender.Image in
                r.clearColor = Color(r: 0, g: 0, b: 0, a: 0)
                defer { r.clearColor = Color(r: 255, g: 255, b: 255) }
                return try r.image(f, scale: 2)
            }
            // The whole texture, made directly, composited the same way (premultiplied over clear).
            let g = ShapeCache.geometry(radius: 14, border: edge, corner: .continuous, shadow: shadow, scale: 2)
            let device = MTLCreateSystemDefaultDevice()!
            let tex = ShapeCache.rasterise(device: device, w: w * 2, h: h * 2, g: g, fill: fill, border: edge,
                                           corner: .continuous, shadow: shadow)!
            var whole = [UInt8](repeating: 0, count: tex.width * tex.height * 4)
            tex.getBytes(&whole, bytesPerRow: tex.width * 4, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
            var worst = 0
            for y in 0..<sliced.height {
                for x in 0..<sliced.width {
                    let tx = x - 36 + g.pad, ty = y - 36 + g.pad
                    for c in 0..<4 {
                        let want = tx >= 0 && ty >= 0 && tx < tex.width && ty < tex.height
                            ? Int(whole[(ty * tex.width + tx) * 4 + c]) : 0
                        worst = max(worst, abs(want - Int(sliced.bgra[(y * sliced.width + x) * 4 + c])))
                    }
                }
            }
            // The fill's antialiasing and the blur's float sums can round one level apart.
            #expect(worst <= 1, "\(w)×\(h): sliced differs from whole by \(worst)")
        }
    }

    @Test func shadowFallsBelowTheRect() throws {
        let d = Draw.shape(R(20, 20, 100, 60), fill: rgb(0xffffff), radius: 14, border: nil, corner: .continuous,
                           shadow: Shadow(color: rgb(0x000000), radius: 6, x: 0, y: 4))
        let img = try render(frame(140, 110, [d]))
        // Under the bottom edge it is darker than above the top edge.
        let below = img.pixel(140, 2 * 82).r, above = img.pixel(140, 2 * 18 - 1).r
        #expect(below < above, "below \(below) above \(above)")
        #expect(img.pixel(140, 100) == rgb(0xffffff))
    }

    /// SwiftUI's rendering of a view, at 2x, as straight alpha (or the brightest channel) per pixel.
    @MainActor static func swiftUI<V: View>(_ v: V, alpha: Bool = true) -> (w: Int, h: Int, values: [Int]) {
        let r = ImageRenderer(content: v)
        r.scale = 2
        let img = r.cgImage!
        let w = img.width, h = img.height
        var b = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, (0..<(w * h)).map { i in alpha ? Int(b[i * 4 + 3]) : Int(max(b[i * 4], b[i * 4 + 1], b[i * 4 + 2])) })
    }

    /// A shape's shadow is SwiftUI's `shadow(color:radius:x:y:)` outside the shape, for small and
    /// large radii. SwiftUI's blur is not exactly Gaussian; they differ by a few levels near
    /// corners (measured worst: 7 at radii 3 and 30).
    @MainActor @Test func shadowsAreSwiftUIs() throws {
        for (radius, y, opacity) in [(3, 0, 0.8), (6, 2, 0.5), (14, 4, 0.35), (30, 4, 0.5)] {
            let theirs = Self.swiftUI(Rectangle().fill(SwiftUI.Color.white).frame(width: 200, height: 100)
                .shadow(color: .black.opacity(opacity), radius: CGFloat(radius), y: CGFloat(y)).padding(100))
            let d = Draw.shape(R(100, 100, 200, 100), fill: rgb(0xffffff), radius: 0, border: nil, corner: .circular,
                               shadow: Shadow(color: Color(r: 0, g: 0, b: 0, a: UInt8((opacity * 255).rounded())),
                                              radius: UInt32(radius), x: 0, y: Int32(y)))
            let ours = try withRenderer { r -> CairnRender.Image in
                r.clearColor = Color(r: 0, g: 0, b: 0, a: 0)
                defer { r.clearColor = Color(r: 255, g: 255, b: 255) }
                return try r.image(frame(400, 300, [d]), scale: 2)
            }
            #expect(ours.width == theirs.w && ours.height == theirs.h)
            var worst = 0
            for py in 0..<ours.height {
                for px in 0..<ours.width where !(px >= 200 && px < 600 && py >= 200 && py < 400) {
                    worst = max(worst, abs(Int(ours.bgra[(py * ours.width + px) * 4 + 3]) - theirs.values[py * theirs.w + px]))
                }
            }
            #expect(worst <= 7, "radius \(radius): shadow differs from SwiftUI's by \(worst) levels")
        }
    }

    /// Text is thickened as AppKit and SwiftUI thicken it (font smoothing): the ink of light and
    /// coloured text on black is SwiftUI's to within 2%.
    @MainActor @Test func textInkIsSwiftUIs() throws {
        guard FontSmoothing.enabled else { return }
        for (c, size, weight) in [((0.93, 0.91, 0.86), 22, 200), ((1.0, 0.30, 0.18), 10, 600), ((0.5, 0.5, 0.5), 14, 400)] {
            let theirs = Self.swiftUI(SwiftUI.Text("0:07 REC typed")
                .font(.system(size: CGFloat(size), weight: weight == 200 ? .thin : weight == 600 ? .semibold : .regular))
                .foregroundStyle(SwiftUI.Color(red: c.0, green: c.1, blue: c.2))
                .padding(10).background(SwiftUI.Color.black), alpha: false)
            let color = Color(r: UInt8((c.0 * 255).rounded()), g: UInt8((c.1 * 255).rounded()), b: UInt8((c.2 * 255).rounded()))
            let ours = try withRenderer { r -> CairnRender.Image in
                r.clearColor = Color(r: 0, g: 0, b: 0)
                defer { r.clearColor = Color(r: 255, g: 255, b: 255) }
                return try r.image(frame(200, 60, [text(10, 30, "0:07 REC typed", font: Font(size: UInt32(size), weight: UInt32(weight)), color: color)]), scale: 2)
            }
            let inkOurs = (0..<(ours.width * ours.height)).reduce(0) { $0 + Int(max(ours.bgra[$1 * 4], ours.bgra[$1 * 4 + 1], ours.bgra[$1 * 4 + 2])) }
            let inkTheirs = theirs.values.reduce(0, +)
            let ratio = Double(inkOurs) / Double(inkTheirs)
            #expect(abs(ratio - 1) < 0.02, "\(size) pt weight \(weight) in \(c): ink \(inkOurs) vs SwiftUI's \(inkTheirs)")
        }
    }

    @Test func unregisteredPainterPaintsNothing() throws {
        let p = Paint(shader: "nobody.registered.this", origin: 0, scalars: [], arrays: [])
        let img = try render(frame(20, 20, [.paint(R(0, 0, 20, 20), p)]))
        #expect(img.pixel(10, 10) == rgb(0xffffff))
    }
}
