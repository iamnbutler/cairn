import AppKit
import CLean
import CairnFrame
import CairnHost
import Metal
import QuartzCore

// Tray (lean/Examples/Tray.lean): a menu bar item with a native menu and an overlay panel, and
// no window, so it runs as an accessory (docs/surfaces.md).
//   CairnTray               put the item in the menu bar
//   CairnTray --selftest    drive the menus and the panel headlessly and check them

let tray = LeanApp(
    module: runtime_initialize_cairn_Examples_Tray_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

/// Tray has no window; this is only the size Lean starts with.
let size = Size(w: 320, h: 120)
let args = CommandLine.arguments

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

/// The menus and the panel through the host's real objects (`SurfaceHost`, detached: nothing
/// reaches the menu bar or the screen), with Lean on its own thread as in the app.
@MainActor
enum SelfTest {
    static func run() {
        _ = NSApplication.shared
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(tray) }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        let host = SurfaceHost(engine: engine, mode: .detached) { NullRenderer() }
        view.onApply = { host.apply($0) }
        var quits = 0
        view.effectHook = { e in
            if case .quit = e { quits += 1; return true }  // recorded, not run
            return false
        }
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }
        view.applyLatestFrame()

        func settle(_ seq: UInt64) {
            guard engine.wait(through: seq) != nil else { fail("no frame through #\(seq)") }
            view.applyLatestFrame()
        }
        guard let menu = host.menu(450) else { fail("no status item at ^450") }
        func item(_ id: String) -> NSMenuItem {
            guard let (m, i) = menu.find(id), let it = m.item(at: i) else { fail("no item \(id)") }
            return it
        }
        func choose(_ id: String) {
            guard let (m, i) = menu.find(id) else { fail("no item \(id)") }
            m.performActionForItem(at: i)
            settle(menu.lastSeq)
        }
        func titles(_ m: NSMenu) -> [String] { m.items.map { $0.isSeparatorItem ? "-" : $0.title } }
        func statusLine() -> String { menu.root.items.first?.title ?? "" }
        var frame: Frame { engine.latest!.frame }

        // Launch: no window (so an accessory), a status item and a hidden panel.
        if frame.windowIndex != nil { fail("Tray has a window") }
        if frame.surfaces.map(\.place) != [450, 452] { fail("surfaces \(frame.surfaces.map(\.place))") }
        let expect = ["0 recent, menu opened 0 times", "-", "Show Overlay", "Keep Recent Items", "Add Item",
                      "Recent Items", "-", "Quit Tray"]
        if titles(menu.root) != expect { fail("menu \(titles(menu.root))") }
        if menu.root.items[0].isEnabled { fail("the status line is enabled") }
        let overlay = item("^454")
        if overlay.keyEquivalent != "o" || overlay.keyEquivalentModifierMask != .command { fail("Show Overlay's shortcut") }
        if item("^455").state != .on { fail("Keep Recent Items is not checked") }
        guard let recent = item("^451").submenu else { fail("no Recent Items submenu") }
        if titles(recent) != ["None yet", "-", "Clear Recent Items"] { fail("recent \(titles(recent))") }
        if recent.items[0].isEnabled || item("^458").isEnabled { fail("None yet or Clear is enabled") }

        // Opening the menu is a press on ^453.
        menu.menuWillOpen(menu.root)
        settle(menu.lastSeq)
        menu.menuDidClose(menu.root)
        settle(menu.lastSeq)
        if statusLine() != "0 recent, menu opened 1 times" { fail("after opening: \(statusLine())") }

        // Add two items; the submenu is rebuilt (its shape changed), the root updated in place.
        let add = item("^456")
        let rebuilds = menu.rebuilds
        choose("^456")
        choose("^456")
        if titles(recent) != ["Item 2", "Item 1", "-", "Clear Recent Items"] { fail("recent \(titles(recent))") }
        if item("^457#1").title != "Item 1" || !item("^458").isEnabled { fail("recent items or Clear") }
        if menu.rebuilds != rebuilds + 1 { fail("rebuilds \(menu.rebuilds - rebuilds), expected 1") }
        if host.statuses[450]?.status.symbol != "tray.full" { fail("symbol \(host.statuses[450]?.status.symbol ?? "")") }
        choose("^457#1")
        if !statusLine().hasSuffix("picked Item 1") { fail("after picking: \(statusLine())") }

        // Keep Recent Items off: the same Add Item, now greyed out; the items are gone.
        choose("^455")
        if item("^456") !== add { fail("Add Item was rebuilt, not updated in place") }
        if add.isEnabled || item("^455").state != .off { fail("Add Item enabled or Keep still checked") }
        if titles(recent) != ["None yet", "-", "Clear Recent Items"] { fail("recent after Keep off \(titles(recent))") }

        // A stale choice (the menu changed while it was open): Lean ignores it.
        let before = frame.surfaces
        menu.choose(add)
        settle(menu.lastSeq)
        if frame.surfaces != before { fail("a disabled Add Item changed the app") }

        // Show the overlay: a panel at the bottom centre, never key, click-through, on every Space.
        choose("^454")
        guard let ps = frame.surface(452), ps.shown, let panel = host.panels[452] else { fail("no overlay") }
        if ps.canvas.size.w != 320 || ps.canvas.size.h <= 40 { fail("overlay size \(ps.canvas.size)") }
        let bars = ps.canvas.draws.filter { if case let .rect(r, _, _, _) = $0 { r.w == 8 } else { false } }
        if bars.count != 24 { fail("\(bars.count) bars") }
        if item("^454").title != "Hide Overlay" { fail("the item says \(item("^454").title)") }
        let p = panel.panel
        if !panel.visible || p.canBecomeKey || p.canBecomeMain || !p.ignoresMouseEvents || p.hidesOnDeactivate
            || p.level != .statusBar || !p.styleMask.contains(.nonactivatingPanel)
            || p.collectionBehavior != PanelHost.behavior || p.isOpaque {
            fail("panel properties")
        }
        if let vf = panel.screenFrame, p.frame != PanelHost.placement(visible: vf, size: ps.canvas.size, anchor: ps.anchor) {
            fail("panel at \(p.frame), screen \(vf)")
        }
        if p.isVisible { fail("a detached panel is on screen") }

        // The waveform: an `every 20` subscription moves it. How fast, and what each tick costs,
        // timed where each frame is published (on the Lean thread), so a stall of this polling
        // thread can't show up as one of the pipeline's.
        let published = Published452()
        let forward = engine.onPublish
        engine.onPublish = { p in
            if let t = overlayTick(p.frame) { published.add(t, hostNow()) }
            forward?(p)
        }
        engine.stats.reset()
        usleep(2_000_000)
        engine.onPublish = forward
        let (ticks, times) = published.take()
        guard let first = ticks.first, let last = ticks.last, let tf = times.first, let tl = times.last, tl > tf
        else { fail("no ticks published in the overlay") }
        let rate = Double(last - first) / (tl - tf)
        let lean = engine.stats.summary(.lean)
        let gaps = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }.sorted()
        if rate < 30 { fail(String(format: "the overlay ticks at %.1f Hz", rate)) }
        // The caption has grown past two lines; the paragraph keeps the last two, with the tick.
        let lines: [String] = frame.surface(452)?.canvas.draws.compactMap { d -> String? in if case let .text(_, _, _, s) = d { s } else { nil } } ?? []
        if lines.count != 2 || overlayTick(frame) == nil { fail("caption lines \(lines)") }

        // Hide it: the panel goes, and the subscription stops.
        choose("^454")
        if panel.visible || frame.surface(452)?.shown == true { fail("the overlay is still shown") }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !engine.world.running.isEmpty {
            if Date() > deadline { fail("subscriptions \(engine.world.running) after hiding") }
            usleep(1000)
        }

        choose("^459")
        if quits != 1 { fail("Quit Tray sent \(quits) quits") }
        engine.stop()
        func q(_ p: Double) -> String { gaps.isEmpty ? "-" : String(format: "%.2f", gaps[min(gaps.count - 1, Int(Double(gaps.count) * p))]) }
        print("selftest: PASS (Tray: accessory, menu tree, open, add/pick, in-place update, stale choice ignored, overlay panel, quit)")
        print(String(format: "  overlay ticks published: %.1f Hz over 2 s (every 20 ms asked)", rate))
        print("  tick → tick at publish, ms: p50 \(q(0.5)) p90 \(q(0.9)) max \(q(1))")
        print("  Lean step+frame+decode per batch while shown, ms: \(lean)")
    }
}

/// The tick number in the overlay's caption. The caption wraps, and a break can fall between
/// "tick" and its number, so the lines are joined first.
nonisolated func overlayTick(_ f: Frame?) -> Int? {
    let lines = f?.surface(452)?.canvas.draws.compactMap { d -> String? in
        if case let .text(_, _, _, s) = d { s } else { nil }
    } ?? []
    let text = lines.joined(separator: " ")
    guard let r = text.range(of: "tick ", options: .backwards) else { return nil }
    return Int(text[r.upperBound...])
}

/// The overlay's tick values and when each was published, from the Lean thread.
final class Published452: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [Int] = []
    private var times: [Double] = []
    func add(_ t: Int, _ at: Double) {
        lock.lock(); defer { lock.unlock() }
        if ticks.last != t { ticks.append(t); times.append(at) }
    }
    func take() -> ([Int], [Double]) { lock.lock(); defer { lock.unlock() }; return (ticks, times) }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Tray", size: size) { LeanCore(tray) })
}
