import Foundation

/// Turns AppKit's fractional scroll deltas into whole logical points without losing any: the
/// remainder carries into the next event, so the sum Lean sees tracks the sum AppKit sent to
/// within one point.
///
/// Sign: positive `dy` scrolls toward the end of the content (the content moves up), like a web
/// `wheel` event's `deltaY`; positive `dx` scrolls toward the right. AppKit's deltas already
/// include the user's natural-scrolling setting.
public struct ScrollAccumulator: Sendable {
    /// Points per line for devices that report lines (a mouse wheel), not pixels.
    public static let lineHeight = 16.0

    private var rx = 0.0, ry = 0.0

    public init() {}

    /// AppKit deltas in, whole points out (nil when both round to zero so far).
    public mutating func add(deltaX: Double, deltaY: Double, precise: Bool) -> (dx: Int32, dy: Int32)? {
        let k = precise ? 1.0 : Self.lineHeight
        rx += -deltaX * k
        ry += -deltaY * k
        let dx = rx.rounded(.towardZero), dy = ry.rounded(.towardZero)
        rx -= dx
        ry -= dy
        if dx == 0 && dy == 0 { return nil }
        return (Int32(clamping: Int(dx)), Int32(clamping: Int(dy)))
    }

    public mutating func reset() { rx = 0; ry = 0 }
}
