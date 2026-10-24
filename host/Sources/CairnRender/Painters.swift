import CairnFrame
import Foundation
import Metal

/// What a painter is given to draw one `paint` draw.
public struct PaintContext {
    /// The draw's data from Lean.
    public let paint: Paint
    /// The box's size in device pixels. The viewport is the box, so a full-viewport triangle
    /// covers exactly it, with uv (0, 0) at its top-left pixel corner.
    public let width: Int, height: Int
    /// Device pixels per logical point.
    public let scale: Float
    /// Seconds since `paint.origin` on the monotonic clock (`CLOCK_MONOTONIC`), at encode time.
    public let seconds: Double
}

/// A host-drawn content node's shader: Metal source with a vertex and fragment function, and the
/// code that sets its inputs from the draw's data and draws.
///
/// The renderer compiles the source once per device and pixel format, with premultiplied
/// blending like every other draw, sets the viewport to the box and the scissor to the box
/// within the clip, then calls `encode`. Everything the encoder draws is cut to the box by that
/// scissor. `encode` may set buffers, bytes and textures and draw, and must not change the
/// viewport, the scissor or the pipeline (trusted: docs/trusted.md, `render.paint.bounds`).
public struct Painter: @unchecked Sendable {
    public let source: String
    public let vertex: String
    public let fragment: String
    public let encode: (MTLRenderCommandEncoder, PaintContext) -> Void

    public init(source: String, vertex: String, fragment: String,
                encode: @escaping (MTLRenderCommandEncoder, PaintContext) -> Void) {
        self.source = source; self.vertex = vertex; self.fragment = fragment; self.encode = encode
    }
}

/// The process's registered painters, by the name a `paint` draw gives. An app registers its own
/// before its first frame; a draw naming an unregistered painter paints nothing.
public enum Painters {
    nonisolated(unsafe) private static var table: [String: Painter] = [:]
    private static let lock = NSLock()

    public static func register(_ name: String, _ painter: Painter) {
        lock.lock(); defer { lock.unlock() }
        table[name] = painter
    }

    public static func named(_ name: String) -> Painter? {
        lock.lock(); defer { lock.unlock() }
        return table[name]
    }

    /// The monotonic clock in nanoseconds, the time base of `Paint.origin` (in ms).
    public static func nowNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    /// Seconds from `originMs` to `nowNs`, negative if the origin is later.
    static func seconds(since originMs: UInt64, nowNs: UInt64) -> Double {
        let o = originMs.multipliedReportingOverflow(by: 1_000_000)
        let originNs = o.overflow ? UInt64.max : o.partialValue
        return nowNs >= originNs ? Double(nowNs - originNs) / 1e9 : -Double(originNs - nowNs) / 1e9
    }
}
