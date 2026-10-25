import AppKit
import CairnFrame
import CairnHost
import Foundation

/// An app that records every event the Lean thread hands it, and draws nothing.
final class PointerLogCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [Event] = []
    var events: [Event] { lock.withLock { received } }
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) { lock.withLock { received += events } }
    func frame() throws -> Frame {
        Frame(size: Size(w: 10, h: 10), draws: [], ax: [], textInput: nil, cursor: .arrow, effects: [])
    }
}

/// Clicks and double clicks (^7, ^214; `HostView`'s mouse handlers). Each case sizes a titled
/// window (never shown) whose content view is the host's `HostView`, then gives AppKit the mouse
/// events a person's clicks make: single clicks, double clicks (the second down and up with
/// `clickCount` 2, within the system's double-click interval) and some triple clicks, each at a
/// random point of the content, fractional points and edges included, with random modifiers.
/// Each goes to the view AppKit's hit testing picks at its window location (`hitTest` on the
/// content's superview, as `NSWindow.sendEvent` does; a window never shown gets no routing from
/// `sendEvent` itself), and the host converts the window's coordinates itself. What the app's
/// core receives, after the engine's queue:
///
/// - `pointer.click`: each click is exactly `pointerMove p`, `pointerDown p primary`,
///   `pointerUp p primary`, in order, with nothing between, where `p` is the clicked point in
///   the content's top-left coordinates rounded down to whole points (computed here from the
///   window's location and the content height, not by the host's `convert`), inside the
///   content, with the event's modifiers;
/// - `pointer.double-click`: the second click of a double click arrives as another
///   `pointerMove p`, `pointerDown p primary` with `clicks: 2` at the same `p`, then its
///   `pointerUp p`; the first click's down has `clicks: 1` (a triple click's third has 3).
final class PointerSuite: Suite {
    let name = "pointer"
    let crashCheck = "pointer.click"
    let checks: [String: CheckInfo] = [
        "pointer.click": CheckInfo(
            title: "The host reports clicks where they happen",
            trusted: ["host/Sources/CairnHost/HostView.swift (mouseDown, mouseUp, point)",
                      "host/Sources/CairnHost/Engine.swift (queue, coalescing)", "AppKit (NSView.hitTest)"],
            oracle: "the click's window location, flipped and rounded down here; the event's modifier flags"),
        "pointer.double-click": CheckInfo(
            title: "The host reports a double click as a second click",
            trusted: ["host/Sources/CairnHost/HostView.swift (mouseDown clickCount)",
                      "host/Sources/CairnHost/Engine.swift", "AppKit (NSView.hitTest)"],
            oracle: "the clickCount AppKit gives each mouse down, at the first click's point"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 5) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!
    var core: PointerLogCore!
    var eventNumber = 0

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

    struct Click: CustomStringConvertible {
        /// The point in the window's coordinates (AppKit's: origin bottom left).
        var x, y: Double
        /// 1: a click, 2: a double click, 3: a triple click.
        var count: Int
        var flags: NSEvent.ModifierFlags
        var description: String {
            let kind = ["", "click", "double click", "triple click"][count]
            return "\(kind) at window (\(x), \(y))\(flags.isEmpty ? "" : " flags \(flags.rawValue)")"
        }
    }

    static func coord(_ g: inout SplitMix, _ max: Int) -> Double {
        switch g.below(8) {
        case 0: 0
        case 1: Double(max) - 0.25
        case 2: Double(g.range(0, max - 1))
        default: Double(g.range(0, max * 64 - 1)) / 64
        }
    }

    static func plan(_ g: inout SplitMix) -> (NSSize, [Click]) {
        let size = NSSize(width: g.range(40, 1600), height: g.range(40, 1000))
        var clicks: [Click] = []
        for _ in 0..<g.range(1, 10) {
            var flags: NSEvent.ModifierFlags = []
            if g.chance(1, 4) { flags.insert(.shift) }
            if g.chance(1, 6) { flags.insert(.command) }
            if g.chance(1, 6) { flags.insert(.option) }
            if g.chance(1, 6) { flags.insert(.control) }
            // AppKit's y is up: the content's top-left row is y = height, and y = 0 is the bottom
            // edge, below the content. So y is drawn from the top down, in (0, height].
            let h = Double(size.height)
            clicks.append(Click(x: coord(&g, Int(size.width)), y: h - min(coord(&g, Int(size.height)), h - 0.25),
                                count: g.weighted([(5, { _ in 1 }), (4, { _ in 2 }), (1, { _ in 3 })]), flags: flags))
        }
        return (size, clicks)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated { runMain(&g, r) }
    }

    @MainActor
    func mouse(_ type: NSEvent.EventType, _ c: Click, clicks: Int, time: TimeInterval) -> NSEvent {
        eventNumber += 1
        return NSEvent.mouseEvent(with: type, location: NSPoint(x: c.x, y: c.y), modifierFlags: c.flags,
                                  timestamp: time, windowNumber: window.windowNumber, context: nil,
                                  eventNumber: eventNumber, clickCount: clicks,
                                  pressure: type == .leftMouseDown ? 1 : 0)!
    }

    @MainActor
    func runMain(_ g: inout SplitMix, _ r: Recorder) {
        let (size, plan) = Self.plan(&g)
        window.setContentSize(size)
        _ = engine.wait(through: engine.lastSeq)
        let height = view.bounds.height
        let before = core.events.count
        // The event, the click it belongs to, and which click of a double or triple click.
        var expected: [(Event, Int, Int)] = []
        let interval = NSEvent.doubleClickInterval
        var misrouted = false
        func deliver(_ e: NSEvent) {
            let hit = window.contentView?.superview?.hitTest(e.locationInWindow)
            guard hit === view else { misrouted = true; return }
            if e.type == .leftMouseDown { view.mouseDown(with: e) } else { view.mouseUp(with: e) }
        }
        for (i, c) in plan.enumerated() {
            let p = Point(x: Int32(c.x.rounded(.down)), y: Int32((Double(height) - c.y).rounded(.down)))
            let mods = Mods(shift: c.flags.contains(.shift), command: c.flags.contains(.command),
                            option: c.flags.contains(.option), control: c.flags.contains(.control))
            var t = ProcessInfo.processInfo.systemUptime
            for k in 1...c.count {
                deliver(mouse(.leftMouseDown, c, clicks: k, time: t))
                deliver(mouse(.leftMouseUp, c, clicks: k, time: t + interval / 8))
                t += interval / 4
                expected += [(.pointerMove(p), i, k), (.pointerDown(p, .primary, clicks: UInt32(k), mods), i, k),
                             (.pointerUp(p, .primary, mods), i, k)]
            }
            if p.x < 0 || p.y < 0 || Double(p.x) >= Double(view.bounds.width) || Double(p.y) >= Double(height) {
                r.fail("pointer.click", "\(c) in a \(size) window: oracle point \(p) outside the content")
            }
        }
        _ = engine.wait(through: engine.lastSeq)
        let got = core.events.dropFirst(before).filter {
            switch $0 {
            case .pointerMove, .pointerDown, .pointerUp, .pointerExit: return true
            default: return false
            }
        }
        if misrouted { r.fail("pointer.click", "AppKit's hit testing picked another view than the HostView") }
        r.ran("pointer.click")
        if plan.contains(where: { $0.count >= 2 }) { r.ran("pointer.double-click") }
        let n = max(got.count, expected.count)
        for j in 0..<n {
            let want = j < expected.count ? expected[j].0 : nil
            let have = j < got.count ? got[got.startIndex + j] : nil
            if want == have { continue }
            let i = j < expected.count ? expected[j].1 : plan.count - 1
            let k = j < expected.count ? expected[j].2 : 1
            // A click after the first of a double or triple click is ^214's; the rest ^7's.
            let check = k >= 2 ? "pointer.double-click" : "pointer.click"
            r.fail(check, "\(plan[i]) in a \(Int(size.width))×\(Int(size.height)) window: event \(j) is \(have.map { "\($0)" } ?? "missing"), want \(want.map { "\($0)" } ?? "nothing")")
            break
        }
        for c in plan {
            r.count("pointer.click", "clicks", c.count)
            if c.count == 2 { r.count("pointer.double-click", "double clicks") }
            if c.count == 3 { r.count("pointer.double-click", "triple clicks") }
            if !c.flags.isEmpty { r.count("pointer.click", "with modifiers") }
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (size, clicks) = Self.plan(&g)
        return "window \(Int(size.width))×\(Int(size.height)), then " + clicks.map(\.description).joined(separator: ", ")
    }
}
