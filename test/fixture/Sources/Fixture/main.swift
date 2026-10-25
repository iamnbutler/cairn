import AppKit
import CFixture
import CLean
import CairnFrame
import CairnHost
import CairnRender
import Metal
import QuartzCore

// Cairn's fixture app (lean/Fixture.lean) on Cairn's host, as an app in its own repository has
// it. `make check` runs `--selftest`, `cairn bench` runs `--bench`, `cairn conformance` runs it
// with its debug socket on.
//   Fixture               open the window
//   Fixture --selftest    drive the host headlessly through its real threads and check it
//   Fixture --bench       input → frame and frame size with 10 and 1,000 items

let fixture = LeanApp(
    module: runtime_initialize_fixture_Fixture_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 480, h: 600)
let args = CommandLine.arguments

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("selftest: FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func center(_ r: Rect) -> Point { Point(x: r.x + r.w / 2, y: r.y + r.h / 2) }

func click(_ p: Point) -> [Event] {
    [.pointerMove(p), .pointerDown(p, .primary, clicks: 1, Mods()), .pointerUp(p, .primary, Mods())]
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

/// The headless check: the real engine (Lean thread, v1 codec, timers), the real view (text
/// input client, accessibility mirror), no window. It types and presses through the entry points
/// AppKit and assistive apps use, waits for a timer the app set, and checks the frame, the AX
/// tree and a painted pixel.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(fixture) }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        @discardableResult
        func settle(_ seq: UInt64 = engine.lastSeq) -> Frame {
            guard let p = engine.wait(through: seq) else { fail("no frame through #\(seq)") }
            view.applyLatestFrame()
            return p.frame
        }
        func elements() -> [NSAccessibilityElement] {
            var out: [NSAccessibilityElement] = []
            func walk(_ xs: [Any]?) {
                for case let e as NSAccessibilityElement in xs ?? [] { out.append(e); walk(e.accessibilityChildren()) }
            }
            walk(view.accessibilityChildren())
            return out
        }
        func need(_ id: String) -> NSAccessibilityElement {
            guard let e = elements().first(where: { $0.accessibilityIdentifier() == id }) else {
                fail("\(id) not in the accessibility tree")
            }
            return e
        }
        func ids(_ prefix: String) -> [String] {
            elements().compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix(prefix) }
        }
        func label(_ suffix: String) -> String? {
            elements().compactMap { e -> String? in
                guard e.accessibilityRole() == .staticText, let l = e.accessibilityLabel(), l.hasSuffix(suffix) else { return nil }
                return l
            }.first
        }
        func press(_ id: String) {
            if !need(id).accessibilityPerformPress() { fail("AXPress on \(id) refused") }
            settle()
        }
        func type(_ s: String) {
            view.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }
        func expect(_ what: String, _ got: some Equatable, _ want: some Equatable) {
            if String(describing: got) != String(describing: want) { fail("\(what): \(got), expected \(want)") }
        }

        var f = settle()
        expect("first frame size", "\(f.size.w)x\(f.size.h)", "480x600")
        if need("^2").accessibilityRole() != .textField { fail("^2 is not a text field") }
        if need("^3").accessibilityRole() != .button { fail("^3 is not a button") }
        expect("left at start", label(" left") ?? "", "0 items left")

        // Focus the field (an AX focus is a click at its centre), type, press Enter.
        need("^2").setAccessibilityFocused(true)
        f = settle()
        if f.textInput?.control.label != "^2" { fail("the field is not focused after an AX focus") }
        type("  Buy milk ")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle()
        expect("checkboxes after Enter", ids("^4"), ["^4#1"])
        expect("item label (trimmed)", need("^4#1").accessibilityLabel() ?? "", "Buy milk")

        // Type again, then press Add; toggle item 1; delete item 2.
        type("Eggs")
        press("^3")
        expect("checkboxes after Add", ids("^4"), ["^4#1", "^4#2"])
        press("^4#1")
        expect("^4#1 value", need("^4#1").accessibilityValue() as? Int ?? -1, 1)
        expect("left after toggle", label(" left") ?? "", "1 item left")
        press("^5#2")
        expect("delete buttons after delete", ids("^5"), ["^5#1"])

        // Flash: its timer comes back through the host's clock, and the note goes.
        press("^6")
        if label("Flashing") == nil { fail("no Flashing note after a press on ^6") }
        let deadline = hostNow() + 5
        while label("Flashing") != nil {
            if hostNow() > deadline { fail("the Flash timer never fired") }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            view.applyLatestFrame()
        }

        // Tab moves keyboard focus in paint order: field, then Add.
        f = settle(engine.send([.pointerExit, .key(.tab, Mods())]))
        expect("focus after Tab", f.ax.first { $0.focused }?.control?.label ?? "none", "^2")
        if view.shadowDivergences.count != 0 { fail("text shadow diverged: \(view.shadowDivergences)") }

        // The frame paints what it says: Add's fill, clear of its label.
        f = settle(engine.send([.key(.escape, Mods())]))
        guard let add = f.ax.first(where: { $0.control?.label == "^3" }) else { fail("^3 not in frame") }
        do {
            let c = try Renderer().probe(f, at: Point(x: add.rect.x + 3, y: add.rect.y + add.rect.h / 2))
            expect("Add fill", "\(c.r),\(c.g),\(c.b)", "0,122,255")
        } catch { fail("render: \(error)") }

        engine.stop()
        print("selftest: PASS (Fixture: focus, type, Enter, Add, toggle, delete, timer, Tab, AX, paint)")
    }
}

/// Lean through the real exports and codec, with no threads: input → frame (encode events, step,
/// frame, decode) and the frame's size in bytes.
enum Bench {
    static func run() {
        LeanRuntime.enter(module: fixture.module)
        let codec = FrameV1Codec()
        print("Fixture bench (release, LEAN_ABORT_ON_NONLINEAR=\(ProcessInfo.processInfo.environment["LEAN_ABORT_ON_NONLINEAR"] ?? "unset"))")
        for n in [10, 1000] {
            var state = cairn_app_init(UInt32(size.w), UInt32(size.h), 200)!
            func step(_ es: [Event]) { state = cairn_app_step(state, LeanRuntime.bytes(codec.encode(es)))! }
            func frame() -> (Frame, Int) {
                cairn_lean_inc(state)
                return try! LeanRuntime.withBytes(cairn_app_frame(state)!) { (try codec.decodeFrame($0), $0.count) }
            }
            func ax(_ id: String) -> Rect {
                guard let r = frame().0.ax.first(where: { $0.control?.label == id })?.rect else { fail("\(id) not in frame") }
                return r
            }
            step(click(center(ax("^2"))))
            var adds: [Event] = []
            for i in 0..<n { adds += [.insertText("Item \(i + 1)"), .key(.enter, Mods())] }
            let t0 = hostNow()
            step(adds)
            let addMs = (hostNow() - t0) * 1000
            let (f, bytes) = frame()
            precondition(f.ax.filter { $0.control?.claim == 4 }.count == n)
            let toggle = center(ax("^4#1"))

            func time(_ label: String, _ events: () -> [Event]) {
                var ms: [Double] = []
                for i in 0..<60 {
                    let es = events()
                    let t0 = hostNow()
                    step(es)
                    _ = frame()
                    if i >= 10 { ms.append((hostNow() - t0) * 1000) }
                }
                ms.sort()
                print(String(format: "    %@: p50 %.3f ms, p95 %.3f ms", label, ms[ms.count / 2], ms[ms.count * 95 / 100]))
            }
            print("  \(n) items: frame \(bytes) bytes, \(f.draws.count) draws, \(f.ax.count) ax nodes; adding them took \(String(format: "%.1f", addMs)) ms")
            time("type one character (field focused)") { [.insertText("x")] }
            time("click a checkbox (move, down, up)") { click(toggle) }
            var x: Int32 = 0
            time("pointer move (hover)") { x = (x + 7) % 400; return [.pointerMove(Point(x: 20 + x, y: 300))] }
            cairn_lean_dec(state)
        }
    }
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

/// Closing the window while work is in flight: the real app (`CairnApp.main`, its window, its
/// delegate) with the debug socket on, so it is shown without taking focus. Once a frame is up,
/// it presses Flash (a timer due 400 ms later), floods the engine with input from another thread,
/// and closes the window as its close button does, with an invisible window of its own still open
/// so the run loop keeps turning. The app must quit within a few seconds, apply no frame after the
/// close, and not crash on a frame hop that lands after it (Pairs 0.1.2 did, on a window AppKit had
/// already freed). `make selftest` runs it.
@MainActor
enum CloseTest {
    static var closedVersion: Int?
    static var closedAt = 0.0
    static var waiting: Timer?
    static var view: HostView?
    static var other: NSWindow?

    static func run() -> Never {
        // Freed memory filled with junk, so a use of the freed window crashes every time rather
        // than most times: malloc reads this at launch, hence the exec.
        if getenv("MallocScribble") == nil {
            setenv("MallocScribble", "1", 1)
            execv(CommandLine.unsafeArgv[0]!, CommandLine.unsafeArgv)
            fail("close-test: couldn't exec itself")
        }
        setenv("CAIRN_DEBUG_SOCKET", "1", 1)  // shown without activating, deaf to the real mouse
        // A run-loop timer, not the main queue: the run loop `close` turns must drain the queue.
        let start = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard closedVersion == nil,
                      let view = NSApp.windows.lazy.compactMap({ $0.contentView as? HostView }).first,
                      view.shown != nil else { return }
                waiting?.invalidate()
                close(view)
            }
        }
        waiting = start
        RunLoop.main.add(start, forMode: .common)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { finish() }
        }
        RunLoop.main.add(Timer(timeInterval: 15, repeats: false) { _ in fail("close-test: still running after 15 s") }, forMode: .common)
        CairnApp.main(CairnApp.Config(title: "Fixture", size: size) { LeanCore(fixture) })
    }

    static func close(_ view: HostView) {
        guard let window = view.window, let frame = view.shown?.frame else { fail("close-test: no window") }
        guard let flash = frame.ax.first(where: { $0.control?.label == "^6" }) else { fail("close-test: ^6 not in frame") }
        let engine = view.engine
        engine.send(click(center(flash.rect)))  // its timer fires after the close
        let flood = Thread {
            for i in 0..<4000 {
                engine.send([.pointerMove(Point(x: Int32(20 + i % 300), y: 300))])
                usleep(250)
            }
        }
        flood.start()
        // Let frames start landing, then close with hops queued behind the close.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        Self.view = view
        // Another window, invisible and deaf, so the app's window isn't AppKit's last: the app
        // must quit because its window closed, and until it does the run loop keeps turning.
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless],
                             backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.alphaValue = 0
        other.ignoresMouseEvents = true
        other.orderFrontRegardless()
        Self.other = other
        closedVersion = view.shown?.version
        closedAt = hostNow()
        window.performClose(nil)
        RunLoop.main.add(Timer(timeInterval: 4, repeats: false) { _ in
            fail("close-test: the app was still running 4 s after its window closed")
        }, forMode: .common)
    }

    static func finish() {
        guard let closedVersion else { fail("close-test: quit before the window closed") }
        if let v = view?.shown?.version, v != closedVersion {
            fail("close-test: frame \(v) applied after the close (at \(closedVersion))")
        }
        print(String(format: "close-test: PASS (closed with input, a timer and frame hops in flight; quit %.0f ms later)",
                     (hostNow() - closedAt) * 1000))
    }
}

if args.contains("--close-test") {
    MainActor.assumeIsolated { CloseTest.run() }
}

if args.contains("--bench") {
    Bench.run()
    exit(0)
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Fixture", size: size) { LeanCore(fixture) })
}
