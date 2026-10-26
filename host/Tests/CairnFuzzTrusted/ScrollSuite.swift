import AppKit
import CairnFrame
import CairnHost
import Foundation

/// Scroll wheel and trackpad scrolls (^1012; `HostView.scrollWheel`, `ScrollAccumulator`). Each
/// case sizes a window (never shown) whose content is the host's `HostView`, then gives the view
/// one gesture of scroll-wheel events at one point: a mouse wheel's line deltas (fractional, as a
/// wheel with acceleration reports them) or a trackpad's precise pixel deltas, a trackpad gesture
/// starting with `began`, along either axis or both, of either sign. The events are made with
/// `CGEvent(scrollWheelEvent2Source:)` and read back as `NSEvent`s, so the deltas, the precision
/// flag and the phase are AppKit's own. What the app's core receives, after the engine's queue:
///
/// - `pointer.scroll`: only `scroll` events, each at the gesture's point in the content's
///   top-left coordinates rounded down to whole points (computed here from the event's window
///   location), whose `dx` and `dy` sum to within one point of the gesture's AppKit deltas
///   negated and, for line deltas, times 16: positive `dy` toward the end of the content, the
///   sign Cairn's runtime moves a scroll box by (`Runtime.wheel`).
final class ScrollSuite: Suite {
    let name = "scroll"
    let crashCheck = "pointer.scroll"
    let checks: [String: CheckInfo] = [
        "pointer.scroll": CheckInfo(
            title: "The host reports scrolls where they happen, toward the end positive",
            trusted: ["host/Sources/CairnHost/HostView.swift (scrollWheel, point)",
                      "host/Sources/CairnHost/Scroll.swift (ScrollAccumulator)",
                      "host/Sources/CairnHost/Engine.swift (queue, coalescing)"],
            oracle: "AppKit's scrollingDeltaX/Y negated and summed (times 16 for line deltas); the event's window location, flipped and rounded down here"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 5) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!
    var core: PointerLogCore!

    func setUp() {
        MainActor.assumeIsolated {
            let core = PointerLogCore()
            self.core = core
            engine = Engine(size: Size(w: 400, h: 300), scalePercent: 200, clock: false) { core }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 400, height: 300))
            view.effectHook = { _ in true }
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            engine.start()
        }
    }

    struct Gesture: CustomStringConvertible {
        var size: NSSize
        /// The point in the window's coordinates (AppKit's: origin bottom left).
        var x, y: Double
        /// Trackpad (pixel deltas, phases) or mouse wheel (line deltas).
        var precise: Bool
        /// Each event's (dx, dy): whole pixels, or lines in 1/64ths.
        var deltas: [(Double, Double)]
        var description: String {
            "\(precise ? "trackpad" : "wheel") at window (\(x), \(y)) in a \(Int(size.width))×\(Int(size.height)) window: "
                + deltas.map { "(\($0.0), \($0.1))" }.joined(separator: " ")
        }
    }

    static func plan(_ g: inout SplitMix) -> Gesture {
        let size = NSSize(width: g.range(40, 1600), height: g.range(40, 1000))
        let precise = g.bool()
        let axes = g.below(4)  // 0, 1: vertical only; 2: horizontal only; 3: both
        var deltas: [(Double, Double)] = []
        func amount(_ g: inout SplitMix) -> Double {
            if precise { return Double(g.weighted([(6, { $0.range(-40, 40) }), (2, { $0.range(-400, 400) }), (1, { $0.elem([1, -1]) })])) }
            return Double(g.weighted([(4, { $0.range(-64, 64) }), (2, { $0.range(-640, 640) }), (1, { $0.range(-8, 8) })])) / 64
        }
        for _ in 0..<g.range(1, 30) {
            let dy = axes == 2 ? 0 : amount(&g)
            let dx = axes == 0 || axes == 1 ? 0 : amount(&g)
            deltas.append((dx, dy))
        }
        let h = Double(size.height)
        return Gesture(size: size, x: PointerSuite.coord(&g, Int(size.width)),
                       y: h - min(PointerSuite.coord(&g, Int(size.height)), h - 0.25),
                       precise: precise, deltas: deltas)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated { runMain(&g, r) }
    }

    /// A scroll-wheel event at window point (x, y), with AppKit's own reading of the deltas.
    @MainActor
    func event(_ gs: Gesture, _ d: (Double, Double), phase: Int64) -> NSEvent {
        let cg: CGEvent
        if gs.precise {
            cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                         wheel1: Int32(d.1), wheel2: Int32(d.0), wheel3: 0)!
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        } else {
            cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: d.1)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: d.0)
        }
        // A CGEvent's location is global, top left; with no window, the NSEvent's
        // `locationInWindow` is that point in AppKit's screen coordinates (bottom left).
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: gs.x, y: screenH - gs.y)
        return NSEvent(cgEvent: cg)!
    }

    @MainActor
    func runMain(_ g: inout SplitMix, _ r: Recorder) {
        let gs = Self.plan(&g)
        window.setContentSize(gs.size)
        _ = engine.wait(through: engine.lastSeq)
        let height = view.bounds.height
        let before = core.events.count
        // A wheel has no phases, so the host carries a fraction from one gesture into the next;
        // start every case from none, with a trackpad gesture's `began` and no movement, as the
        // host drops it then.
        var start = gs
        start.precise = true
        view.scrollWheel(with: event(start, (0, 0), phase: 1))
        var sumX = 0.0, sumY = 0.0
        var at: NSPoint? = nil
        for (i, d) in gs.deltas.enumerated() {
            // kCGScrollPhaseBegan = 1, Changed = 2.
            let e = event(gs, d, phase: i == 0 ? 1 : 2)
            if at == nil { at = e.locationInWindow }
            if e.locationInWindow != at {
                r.fail("pointer.scroll", "\(gs): AppKit moved the event's location to \(e.locationInWindow)")
                return
            }
            if e.hasPreciseScrollingDeltas != gs.precise {
                r.fail("pointer.scroll", "\(gs): hasPreciseScrollingDeltas is \(e.hasPreciseScrollingDeltas)")
                return
            }
            let k = e.hasPreciseScrollingDeltas ? 1.0 : ScrollAccumulator.lineHeight
            sumX += -e.scrollingDeltaX * k
            sumY += -e.scrollingDeltaY * k
            view.scrollWheel(with: e)
        }
        _ = engine.wait(through: engine.lastSeq)
        guard let loc = at else { return }
        let p = Point(x: Int32(loc.x.rounded(.down)), y: Int32((Double(height) - loc.y).rounded(.down)))
        if p.x < 0 || p.y < 0 || Double(p.x) >= Double(view.bounds.width) || Double(p.y) >= Double(height) {
            // The screen's frame moved the point out of the content (no screen, or a short one).
            r.count("pointer.scroll", "outside the content, skipped")
            return
        }
        r.ran("pointer.scroll")
        r.count("pointer.scroll", gs.precise ? "trackpad gestures" : "wheel gestures")
        r.count("pointer.scroll", "scroll events", gs.deltas.count)
        var gotX: Int64 = 0, gotY: Int64 = 0
        for ev in core.events.dropFirst(before) {
            guard case .scroll(let q, let dx, let dy) = ev else {
                r.fail("pointer.scroll", "\(gs): the core got \(ev), not a scroll")
                return
            }
            if q != p {
                r.fail("pointer.scroll", "\(gs): a scroll at \(q), want \(p)")
                return
            }
            gotX += Int64(dx); gotY += Int64(dy)
        }
        if abs(Double(gotX) - sumX) >= 1 || abs(Double(gotY) - sumY) >= 1 {
            r.fail("pointer.scroll", "\(gs): the core's scrolls sum to (\(gotX), \(gotY)), AppKit's deltas to (\(sumX), \(sumY)) points toward the end")
        }
        if (sumY >= 1 && gotY <= 0) || (sumY <= -1 && gotY >= 0) {
            r.fail("pointer.scroll", "\(gs): dy has the wrong sign: \(gotY) for \(sumY)")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        Self.plan(&g).description
    }
}
