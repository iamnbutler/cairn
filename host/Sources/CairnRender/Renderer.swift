import CairnFrame
import CoreText
import Foundation
import Metal
import QuartzCore
import simd

/// Must match `RectI` in the shader: four float4-sized fields, 64-byte stride.
struct RectInstance {
    var rect: SIMD4<Float>
    var fill: SIMD4<Float>
    var border: SIMD4<Float>
    var shape: SIMD2<Float>
    var pad: SIMD2<Float> = .zero
}

/// Must match `GlyphI` in the shader: four float4s, 64-byte stride.
struct GlyphInstance {
    var rect: SIMD4<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
    var misc: SIMD4<Float>
}

/// A clip in device pixels, half-open: [x0, x1) × [y0, y1).
struct PixelRect: Equatable {
    var x0, y0, x1, y1: Int
    var isEmpty: Bool { x1 <= x0 || y1 <= y0 }

    func intersect(_ o: PixelRect) -> PixelRect {
        PixelRect(x0: max(x0, o.x0), y0: max(y0, o.y0), x1: min(x1, o.x1), y1: min(y1, o.y1))
    }

    /// Logical coordinate to device-pixel edge: ⌈v·s − ½⌉, i.e. round half down. Rects and clips
    /// snap each edge with this one function, never origin and size separately, so two boxes
    /// that share an edge in logical points share it in device pixels at any scale (no seams at
    /// 1.5x), and a clip covers exactly the pixels a fill of the same rect covers. The pixels
    /// between two snapped edges are those whose centres lie inside the logical rect.
    static func edge(_ v: Int64, scale: Float) -> Int {
        Int((Double(v) * Double(scale) - 0.5).rounded(.up))
    }

    static func covering(_ r: Rect, scale: Float) -> PixelRect {
        let x0 = edge(Int64(r.x), scale: scale), y0 = edge(Int64(r.y), scale: scale)
        let x1 = r.w > 0 ? edge(Int64(r.x) + Int64(r.w), scale: scale) : x0
        let y1 = r.h > 0 ? edge(Int64(r.y) + Int64(r.h), scale: scale) : y0
        return PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)
    }
}

/// What `draw` did, for tests and benchmarks.
public struct RenderStats: Equatable, Sendable {
    public var rects = 0, glyphs = 0
    public var rectBatches = 0, glyphBatches = 0
    public var skipped = 0  // draws dropped by an empty clip or a zero-size rect
    public var unbalancedPops = 0
    public var shapes = 0, paints = 0
}

/// Paints a frame's draw list with Metal: rounded, bordered rects by SDF, glyph runs from a
/// Core Text–rasterised atlas, shapes (continuous corners, shadows) from Core Graphics, and
/// host-drawn content by registered painters, under a scissor clip stack, strictly in list order.
///
/// Not thread-safe: use one renderer from one thread (the render thread). Text shaping goes
/// through `TextSystem.shared`, which is safe to share with the metrics export.
public final class Renderer {
    public let device: MTLDevice
    public var clearColor = Color(r: 255, g: 255, b: 255, a: 255)
    public private(set) var lastStats = RenderStats()

    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [MTLPixelFormat: (rect: MTLRenderPipelineState, glyph: MTLRenderPipelineState)] = [:]
    let atlas: GlyphAtlas
    let shapes: ShapeCache
    private var painterPipelines: [String: MTLRenderPipelineState] = [:]
    private let emptyMask: MTLTexture
    private let emptyColor: MTLTexture

    /// Frames that may be in flight at once; each owns a slot of instance buffers.
    static let framesInFlight = 3
    private let inflight = DispatchSemaphore(value: framesInFlight)
    private var slots: [Slot]
    private var slot = 0
    private var lastCommand: MTLCommandBuffer?

    private final class Slot {
        var rects: MTLBuffer?
        var glyphs: MTLBuffer?
    }

    private enum Kind { case rects, glyphs, shape, paint }
    private struct Batch {
        var kind: Kind
        var start: Int
        var count: Int
        var clip: PixelRect
        var maskPage: Int32 = -1
        var colorPage: Int32 = -1
        /// `.shape`: the texture in this frame's `textures`; `.paint`: the index in `paints`.
        var item = -1
    }

    private struct PaintItem { let paint: Paint; let painter: Painter; let box: PixelRect }

    public init(device: MTLDevice? = nil) throws {
        precondition(MemoryLayout<RectInstance>.stride == 64, "RectInstance layout drifted from the shader")
        precondition(MemoryLayout<GlyphInstance>.stride == 64, "GlyphInstance layout drifted from the shader")
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
        self.device = device
        queue = device.makeCommandQueue()!
        library = try device.makeLibrary(source: shaderSource, options: nil)
        atlas = GlyphAtlas(device: device)
        shapes = ShapeCache(device: device)
        emptyMask = Self.blank(device, .r8Unorm)
        emptyColor = Self.blank(device, .bgra8Unorm)
        slots = (0..<Self.framesInFlight).map { _ in Slot() }
    }

    // MARK: Public entry points

    /// Paints `frame` into `texture` (any size; `scale` maps logical points to its pixels),
    /// clearing it to `clearColor` first. Commits and returns the command buffer; call
    /// `waitUntilCompleted()` on it before reading the texture back.
    /// `time` is the monotonic clock in nanoseconds that painters see (default: now).
    @discardableResult
    public func draw(frame: Frame, into texture: MTLTexture, scale: Float,
                     time: UInt64 = Painters.nowNs()) -> MTLCommandBuffer {
        autoreleasepool {
            let cmd = encode(frame: frame, into: texture, scale: scale, time: time)
            cmd.commit()
            lastCommand = cmd
            return cmd
        }
    }

    /// Paints `frame` into a drawable and presents it. Wrapped in an autorelease pool, so a
    /// long-lived render thread doesn't keep drawables alive.
    public func draw(frame: Frame, into drawable: CAMetalDrawable, scale: Float,
                     time: UInt64 = Painters.nowNs()) {
        autoreleasepool {
            let cmd = encode(frame: frame, into: drawable.texture, scale: scale, time: time)
            cmd.present(drawable)
            cmd.commit()
            lastCommand = cmd
        }
    }

    // MARK: Encoding

    func encode(frame: Frame, into texture: MTLTexture, scale: Float, time: UInt64) -> MTLCommandBuffer {
        if atlas.pageCount > GlyphAtlas.maxPages {
            // Pages are append-only while frames are in flight; dropping them needs an idle GPU.
            lastCommand?.waitUntilCompleted()
            atlas.reset()
        }
        inflight.wait()
        let cmd = queue.makeCommandBuffer()!
        let sem = inflight
        cmd.addCompletedHandler { _ in sem.signal() }

        var rects: [RectInstance] = []
        var glyphs: [GlyphInstance] = []
        var batches: [Batch] = []
        var textures: [MTLTexture] = []
        var paints: [PaintItem] = []
        var stats = RenderStats()
        build(frame.draws, scale: scale,
              bounds: PixelRect(x0: 0, y0: 0, x1: texture.width, y1: texture.height),
              rects: &rects, glyphs: &glyphs, batches: &batches, textures: &textures,
              paints: &paints, stats: &stats)
        lastStats = stats

        let s = slots[slot]
        slot = (slot + 1) % slots.count
        let rectBuf = Self.upload(device, rects, into: &s.rects)
        let glyphBuf = Self.upload(device, glyphs, into: &s.glyphs)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        let c = clearColor
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(c.r) / 255 * Double(c.a) / 255, green: Double(c.g) / 255 * Double(c.a) / 255,
            blue: Double(c.b) / 255 * Double(c.a) / 255, alpha: Double(c.a) / 255)
        pass.colorAttachments[0].storeAction = .store
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        let pipe = pipeline(texture.pixelFormat)
        var viewport = SIMD2<Float>(Float(texture.width), Float(texture.height))
        let fullViewport = MTLViewport(originX: 0, originY: 0, width: Double(texture.width),
                                       height: Double(texture.height), znear: 0, zfar: 1)
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        var current: Kind?
        for b in batches {
            enc.setScissorRect(MTLScissorRect(x: b.clip.x0, y: b.clip.y0,
                                              width: b.clip.x1 - b.clip.x0, height: b.clip.y1 - b.clip.y0))
            switch b.kind {
            case .rects:
                if current != .rects {
                    enc.setRenderPipelineState(pipe.rect)
                    enc.setVertexBuffer(rectBuf, offset: 0, index: 0)
                    current = .rects
                }
                enc.setVertexBufferOffset(b.start * MemoryLayout<RectInstance>.stride, index: 0)
                stats.rectBatches += 1
            case .glyphs, .shape:
                if current != .glyphs {
                    enc.setRenderPipelineState(pipe.glyph)
                    enc.setVertexBuffer(glyphBuf, offset: 0, index: 0)
                    current = .glyphs
                }
                enc.setVertexBufferOffset(b.start * MemoryLayout<GlyphInstance>.stride, index: 0)
                if b.kind == .shape {
                    enc.setFragmentTexture(emptyMask, index: 0)
                    enc.setFragmentTexture(textures[b.item], index: 1)
                } else {
                    enc.setFragmentTexture(b.maskPage >= 0 ? atlas.maskPages[Int(b.maskPage)] : emptyMask, index: 0)
                    enc.setFragmentTexture(b.colorPage >= 0 ? atlas.colorPages[Int(b.colorPage)] : emptyColor, index: 1)
                    stats.glyphBatches += 1
                }
            case .paint:
                let item = paints[b.item]
                guard let state = painterPipeline(item.paint.shader, item.painter, texture.pixelFormat) else { continue }
                enc.setRenderPipelineState(state)
                enc.setViewport(MTLViewport(originX: Double(item.box.x0), originY: Double(item.box.y0),
                                            width: Double(item.box.x1 - item.box.x0),
                                            height: Double(item.box.y1 - item.box.y0), znear: 0, zfar: 1))
                item.painter.encode(enc, PaintContext(
                    paint: item.paint, width: item.box.x1 - item.box.x0, height: item.box.y1 - item.box.y0,
                    scale: scale, seconds: Painters.seconds(since: item.paint.origin, nowNs: time)))
                enc.setViewport(fullViewport)
                enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
                current = nil
                continue
            }

            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: b.count)
        }
        enc.endEncoding()
        lastStats = stats
        return cmd
    }

    /// Turns the draw list into instance arrays and an ordered list of batches. Consecutive
    /// draws of the same kind under the same clip share a batch (one instanced draw call); any
    /// change of kind, clip, or atlas page starts a new one, so list order is paint order.
    private func build(_ draws: [Draw], scale: Float, bounds: PixelRect,
                       rects: inout [RectInstance], glyphs: inout [GlyphInstance],
                       batches: inout [Batch], textures: inout [MTLTexture], paints: inout [PaintItem],
                       stats: inout RenderStats) {
        var clips: [PixelRect] = [bounds]
        rects.reserveCapacity(draws.count)
        for d in draws {
            let clip = clips[clips.count - 1]
            switch d {
            case .pushClip(let r):
                clips.append(clip.intersect(PixelRect.covering(r, scale: scale)))
            case .popClip:
                if clips.count > 1 { clips.removeLast() } else { stats.unbalancedPops += 1 }
            case let .rect(r, fill, radius, border):
                let px = PixelRect.covering(r, scale: scale)
                guard !clip.isEmpty, !px.isEmpty, fill != nil || border != nil,
                      !clip.intersect(px).isEmpty else {
                    stats.skipped += 1; continue
                }
                let w = Float(px.x1 - px.x0), h = Float(px.y1 - px.y0)
                // Border widths round half down but never vanish: a 1 pt border is at least 1 px.
                let bw = border.map { $0.width == 0 ? 0 : max(1, Float(Self.edgeLength($0.width, scale))) } ?? 0
                rects.append(RectInstance(
                    rect: SIMD4(Float(px.x0), Float(px.y0), w, h),
                    fill: fill.map(premultiplied) ?? .zero,
                    border: border.map { premultiplied($0.color) } ?? .zero,
                    shape: SIMD2(min(Float(radius) * scale, min(w, h) / 2), bw)))
                stats.rects += 1
                if let last = batches.last, last.kind == .rects, last.clip == clip {
                    batches[batches.count - 1].count += 1
                } else {
                    batches.append(Batch(kind: .rects, start: rects.count - 1, count: 1, clip: clip))
                }
            case let .text(origin, font, color, string):
                guard !clip.isEmpty, !string.isEmpty else { stats.skipped += 1; continue }
                appendText(origin: origin, font: font, color: color, string: string, scale: scale,
                           clip: clip, glyphs: &glyphs, batches: &batches, stats: &stats)
            case let .shape(r, fill, radius, border, corner, shadow):
                let px = PixelRect.covering(r, scale: scale)
                guard !clip.isEmpty, !px.isEmpty, fill != nil || border != nil,
                      let e = shapes.entry(fill: fill, radius: radius, border: border, corner: corner,
                                           shadow: fill == nil ? nil : shadow, scale: scale,
                                           w: px.x1 - px.x0, h: px.y1 - px.y0) else {
                    stats.skipped += 1; continue
                }
                textures.append(e.texture)
                let start = glyphs.count
                for q in ShapeCache.quads(e, px) {
                    glyphs.append(GlyphInstance(rect: q.rect, uv: q.uv, color: SIMD4(1, 1, 1, 1),
                                                misc: SIMD4(1, 0, 0, 0)))
                }
                batches.append(Batch(kind: .shape, start: start, count: glyphs.count - start, clip: clip,
                                     item: textures.count - 1))
                stats.shapes += 1
            case let .paint(r, p):
                let px = PixelRect.covering(r, scale: scale)
                let cut = clip.intersect(px)
                guard !cut.isEmpty, let painter = Painters.named(p.shader) else { stats.skipped += 1; continue }
                paints.append(PaintItem(paint: p, painter: painter, box: px))
                batches.append(Batch(kind: .paint, start: 0, count: 0, clip: cut, item: paints.count - 1))
                stats.paints += 1
            }
        }
    }

    private func appendText(origin: Point, font: Font, color: Color, string: String, scale: Float,
                            clip: PixelRect, glyphs: inout [GlyphInstance],
                            batches: inout [Batch], stats: inout RenderStats) {
        let line = TextSystem.shared.shape(font, string)
        let tint = premultiplied(color)
        let smoothing = FontSmoothing.key(color)
        let s = Double(scale)
        let bins = GlyphAtlas.subpixelBins
        for run in line.runs {
            for i in 0..<run.glyphs.count {
                let p = run.positions[i]
                // Core Graphics quantises a glyph's x to a quarter point (measured against
                // SwiftUI: exact at 2x), so text lands where AppKit and SwiftUI put it.
                let xpt = Double(origin.x) + Double(p.x)
                let ox = run.isColor ? xpt * s : (xpt * 4).rounded(.down) / 4 * s
                let oy = ((Double(origin.y) - Double(p.y)) * s).rounded()
                var bx = ox.rounded(.down)
                var bin = 0
                if run.isColor {
                    bx = ox.rounded()
                } else {
                    bin = Int(((ox - bx) * Double(bins)).rounded())
                    if bin == bins { bin = 0; bx += 1 }
                }
                let g = atlas.glyph(run.font, run.glyphs[i], bin: bin, scale: scale, isColor: run.isColor,
                                    smoothing: smoothing)
                guard g.page >= 0 else { continue }
                glyphs.append(GlyphInstance(
                    rect: SIMD4(Float(bx) + Float(g.left), Float(oy) - Float(g.top), Float(g.w), Float(g.h)),
                    uv: SIMD4(Float(g.x), Float(g.y), Float(g.x) + Float(g.w), Float(g.y) + Float(g.h)),
                    color: tint,
                    misc: SIMD4(run.isColor ? 1 : 0, 0, 0, 0)))
                stats.glyphs += 1
                if var last = batches.last, last.kind == .glyphs, last.clip == clip,
                   last.start + last.count == glyphs.count - 1 {
                    let ok = g.isColor
                        ? (last.colorPage < 0 || last.colorPage == g.page)
                        : (last.maskPage < 0 || last.maskPage == g.page)
                    if ok {
                        if g.isColor { last.colorPage = g.page } else { last.maskPage = g.page }
                        last.count += 1
                        batches[batches.count - 1] = last
                        continue
                    }
                }
                var b = Batch(kind: .glyphs, start: glyphs.count - 1, count: 1, clip: clip)
                if g.isColor { b.colorPage = g.page } else { b.maskPage = g.page }
                batches.append(b)
            }
        }
    }

    // MARK: Helpers

    /// A logical length in whole device pixels, rounded half down.
    static func edgeLength(_ v: UInt32, _ scale: Float) -> Int {
        Int((Double(v) * Double(scale) - 0.5).rounded(.up))
    }

    private func pipeline(_ format: MTLPixelFormat) -> (rect: MTLRenderPipelineState, glyph: MTLRenderPipelineState) {
        if let p = pipelines[format] { return p }
        func make(_ v: String, _ f: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v)
            d.fragmentFunction = library.makeFunction(name: f)
            let a = d.colorAttachments[0]!
            a.pixelFormat = format
            a.isBlendingEnabled = true
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        let p = (make("rect_vertex", "rect_fragment"), make("glyph_vertex", "glyph_fragment"))
        pipelines[format] = p
        return p
    }

    private func painterPipeline(_ name: String, _ p: Painter, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = "\(format.rawValue) \(name)"
        if let s = painterPipelines[key] { return s }
        guard let lib = try? device.makeLibrary(source: p.source, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: p.vertex)
        d.fragmentFunction = lib.makeFunction(name: p.fragment)
        let a = d.colorAttachments[0]!
        a.pixelFormat = format
        a.isBlendingEnabled = true
        a.sourceRGBBlendFactor = .one
        a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard d.vertexFunction != nil, d.fragmentFunction != nil,
              let s = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        painterPipelines[key] = s
        return s
    }

    private static func upload<T>(_ device: MTLDevice, _ items: [T], into buf: inout MTLBuffer?) -> MTLBuffer? {
        guard !items.isEmpty else { return buf }
        let bytes = items.count * MemoryLayout<T>.stride
        if buf == nil || buf!.length < bytes {
            var cap = 64 * 1024
            while cap < bytes { cap *= 2 }
            buf = device.makeBuffer(length: cap, options: .storageModeShared)
        }
        items.withUnsafeBytes { src in buf!.contents().copyMemory(from: src.baseAddress!, byteCount: bytes) }
        return buf
    }

    private static func blank(_ device: MTLDevice, _ format: MTLPixelFormat) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 1, height: 1, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        let t = device.makeTexture(descriptor: d)!
        let zero = [UInt8](repeating: 0, count: 4)
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: zero,
                  bytesPerRow: format == .r8Unorm ? 1 : 4)
        return t
    }
}

public enum RenderError: Error { case noDevice, textureAllocation }

/// sRGB-encoded 8-bit colour to premultiplied floats. Blending happens on the encoded values
/// (the target is `bgra8Unorm`, not `_srgb`), as AppKit's own compositing of UI colours does.
func premultiplied(_ c: Color) -> SIMD4<Float> {
    let a = Float(c.a) / 255
    return SIMD4(Float(c.r) / 255 * a, Float(c.g) / 255 * a, Float(c.b) / 255 * a, a)
}
