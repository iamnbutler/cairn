import CairnFrame
import CairnRender
import Foundation
import Metal

/// Host-drawn content (`paint` draws, docs/frame.md): a painter's pixels stay inside its box.
///
/// Each case renders a random frame offscreen with paint draws in it (Yap's tape with random,
/// often malformed data; a painter whose triangle covers far more than the viewport; one whose
/// triangles land anywhere; an unregistered name), at a random scale and time, under random
/// clips, between random rects and text, then renders the same frame with the paint draws
/// removed. Every pixel outside the union of the paint boxes (snapped to pixels as the renderer
/// snaps rects, and cut to the clip in force) must be the same in both pictures.
final class PaintSuite: Suite {
    let name = "paint"
    let crashCheck = "render.paint.bounds"
    let checks: [String: CheckInfo] = [
        "render.paint.bounds": CheckInfo(
            title: "A paint draw changes no pixel outside its box within the clip",
            trusted: ["host/Sources/CairnRender/Renderer.swift (paint batches: viewport and scissor)",
                      "host/Sources/CairnRender/Painters.swift", "host/Tests/CairnFuzzTrusted/YapTape.swift",
                      "Metal (scissor test)"],
            oracle: "the same frame rendered without its paint draws, compared pixel by pixel"),
    ]

    func cases(for n: Int) -> Int { max(10, n / 4) }

    nonisolated(unsafe) static var renderer: Renderer?

    func setUp() {
        YapTape.register()
        Painters.register("fuzz.flood", Painter(source: Self.shaders, vertex: "floodVertex", fragment: "solidFragment") { enc, _ in
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        })
        Painters.register("fuzz.scatter", Painter(source: Self.shaders, vertex: "scatterVertex", fragment: "solidFragment") { enc, ctx in
            // Triangles anywhere: clip-space coordinates from the scalars, in hundredths, ±21 million.
            var xs = ctx.paint.scalars.map { Float($0) / 100 }
            let n = xs.count / 6 * 3
            guard n > 0 else { return }
            enc.setVertexBytes(&xs, length: xs.count * 4, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)
        })
        if Self.renderer == nil { Self.renderer = try? Renderer() }
    }

    static let shaders = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 p [[position]]; };
    vertex V floodVertex(uint id [[vertex_id]]) {
        float2 q[3] = { float2(-50, -50), float2(150, -50), float2(-50, 150) };
        V o; o.p = float4(q[id], 0, 1); return o;
    }
    vertex V scatterVertex(uint id [[vertex_id]], constant float2 *xs [[buffer(0)]]) {
        V o; o.p = float4(xs[id], 0, 1); return o;
    }
    fragment float4 solidFragment(V in [[stage_in]]) {
        return float4(fract(in.p.x * 0.37), fract(in.p.y * 0.53), 0.8, 1.0);
    }
    """

    struct Case {
        var scale: Float
        var time: UInt64
        var frame: Frame
        var description: String { "scale \(scale) time \(time)\n" + Dump.canvas(frame.window) }
    }

    static func rect(_ g: inout SplitMix, _ w: Int32, _ h: Int32) -> Rect {
        g.weighted([
            (6, { Rect(x: Int32($0.range(-20, Int(w))), y: Int32($0.range(-20, Int(h))),
                       w: Int32($0.range(0, Int(w) + 20)), h: Int32($0.range(0, Int(h) + 20))) }),
            (1, { Rect(x: Int32($0.range(-5, 5)), y: Int32($0.range(-5, 5)), w: Int32($0.range(0, 3)), h: Int32($0.range(0, 3))) }),
            (1, { _ in Rect(x: Int32.min, y: Int32.max, w: Int32.max, h: Int32.max) }),
            (1, { Rect(x: Int32($0.range(-100000, 100000)), y: Int32($0.range(-100000, 100000)),
                       w: Int32($0.range(0, 200000)), h: Int32($0.range(0, 200000))) }),
        ])
    }

    static func ints(_ g: inout SplitMix, _ max: Int) -> [Int32] {
        (0..<g.range(0, max)).map { _ in
            g.weighted([(6, { Int32($0.range(-2000, 6000)) }), (1, { _ in Int32.min }), (1, { _ in Int32.max }),
                        (2, { Int32(truncatingIfNeeded: $0.next()) })])
        }
    }

    static func paint(_ g: inout SplitMix) -> Paint {
        let shader = g.weighted([(4, { _ in YapTape.name }), (2, { _ in "fuzz.flood" }), (2, { _ in "fuzz.scatter" }),
                                 (1, { _ in "no.such.painter" })])
        let origin: UInt64 = g.weighted([(4, { UInt64($0.range(0, 100_000)) }), (1, { _ in UInt64.max }), (1, { $0.next() })])
        var scalars = ints(&g, 40)
        if shader == YapTape.name, g.chance(2, 3) {
            scalars = [Int32(g.range(0, 10000)), Int32(g.range(0, 10000)), Int32(g.range(0, 10000)),
                       Int32(g.below(2)), Int32(g.range(-1000, 5000)), Int32(g.range(-1, 9000))]
        }
        let arrays = (0..<g.range(0, 4)).map { _ in ints(&g, g.chance(1, 4) ? 400 : 20) }
        return Paint(shader: shader, origin: origin, scalars: scalars, arrays: arrays)
    }

    func gen(_ g: inout SplitMix) -> Case {
        let scale: Float = g.elem([1, 1.5, 2, 2, 3])
        let w = Int32(g.range(1, 160)), h = Int32(g.range(1, 120))
        var draws: [Draw] = []
        var depth = 0
        for _ in 0..<g.range(1, 8) {
            switch g.below(6) {
            case 0, 1:
                draws.append(.rect(Self.rect(&g, w, h), fill: Color(r: UInt8(g.below(256)), g: UInt8(g.below(256)),
                                                                     b: UInt8(g.below(256)), a: UInt8(g.below(256))),
                                   radius: UInt32(g.below(10)), border: nil))
            case 2:
                draws.append(.pushClip(Self.rect(&g, w, h))); depth += 1
            case 3 where depth > 0:
                draws.append(.popClip); depth -= 1
            case 4:
                draws.append(.text(origin: Point(x: Int32(g.range(-10, Int(w))), y: Int32(g.range(0, Int(h) + 10))),
                                   font: Font(size: UInt32(g.range(8, 30))), color: Color(r: 0, g: 0, b: 0), string: "Tape 0:07"))
            default:
                draws.append(.paint(Self.rect(&g, w, h), Self.paint(&g)))
            }
        }
        if !draws.contains(where: { if case .paint = $0 { true } else { false } }) {
            draws.insert(.paint(Self.rect(&g, w, h), Self.paint(&g)), at: g.range(0, draws.count))
        }
        let time: UInt64 = g.weighted([(4, { UInt64($0.range(0, 200_000)) * 1_000_000 }), (1, { $0.next() })])
        return Case(scale: scale, time: time, frame: Frame(size: Size(w: w, h: h), draws: draws))
    }

    /// ⌈v·s − ½⌉, the renderer's edge rule (`PixelRect.edge`).
    static func edge(_ v: Int64, _ s: Float) -> Int { Int((Double(v) * Double(s) - 0.5).rounded(.up)) }

    struct Box { var x0, y0, x1, y1: Int
        func meet(_ o: Box) -> Box { Box(x0: max(x0, o.x0), y0: max(y0, o.y0), x1: min(x1, o.x1), y1: min(y1, o.y1)) }
        func contains(_ x: Int, _ y: Int) -> Bool { x >= x0 && x < x1 && y >= y0 && y < y1 }
    }

    static func covering(_ r: Rect, _ s: Float) -> Box {
        let x0 = edge(Int64(r.x), s), y0 = edge(Int64(r.y), s)
        return Box(x0: x0, y0: y0, x1: r.w > 0 ? edge(Int64(r.x) + Int64(r.w), s) : x0,
                   y1: r.h > 0 ? edge(Int64(r.y) + Int64(r.h), s) : y0)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let c = gen(&g)
        let check = "render.paint.bounds"
        guard let renderer = Self.renderer else { r.fail(check, "no Metal device"); return }
        // Where paints may change pixels: each box within the clip in force.
        let pw = Int((Float(c.frame.size.w) * c.scale).rounded(.up)), ph = Int((Float(c.frame.size.h) * c.scale).rounded(.up))
        var clips = [Box(x0: 0, y0: 0, x1: max(1, pw), y1: max(1, ph))]
        var allowed: [Box] = []
        var without: [Draw] = []
        for d in c.frame.draws {
            switch d {
            case let .pushClip(rc): clips.append(clips.last!.meet(Self.covering(rc, c.scale))); without.append(d)
            case .popClip: if clips.count > 1 { clips.removeLast() }; without.append(d)
            case let .paint(rc, p):
                allowed.append(clips.last!.meet(Self.covering(rc, c.scale)))
                r.count(check, p.shader)
            default: without.append(d)
            }
        }
        var bare = c.frame
        bare.draws = without
        do {
            let a = try renderer.image(c.frame, scale: c.scale, time: c.time)
            let b = try renderer.image(bare, scale: c.scale, time: c.time)
            r.ran(check)
            var inside = 0
            for y in 0..<a.height {
                for x in 0..<a.width {
                    let i = (y * a.width + x) * 4
                    guard a.bgra[i..<(i + 4)] != b.bgra[i..<(i + 4)] else { continue }
                    if allowed.contains(where: { $0.contains(x, y) }) { inside += 1; continue }
                    r.fail(check, "pixel (\(x), \(y)) changed outside every paint box \(allowed)", repro: { c.description })
                    return
                }
            }
            r.count(check, inside > 0 ? "paintedInside" : "nothingPainted")
        } catch {
            r.fail(check, "render failed: \(error)", repro: { c.description })
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "paint bounds on " + gen(&g).description
    }
}
