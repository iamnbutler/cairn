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
//   Fixture --scroll-shots <dir>   offscreen renders of the virtual list: at the top, scrolled,
//                         with a row selected, and at the end (docs/media.md, "Stills")
//   Fixture --like-frames <dir>    offscreen frames, 30 a second, of the Like buttons pressed
//                         against a scripted server: one write accepted, one refused and rolled
//                         back, one whose reply is lost and read back (docs/media.md)

// region: fixture-leanapp
let fixture = LeanApp(
    module: runtime_initialize_fixture_Fixture_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())
// endregion: fixture-leanapp

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

        // region: fixture-selftest
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
        // endregion: fixture-selftest

        // region: fixture-selftest-timer
        // Flash: its timer comes back through the host's clock, and the note goes.
        press("^6")
        if label("Flashing") == nil { fail("no Flashing note after a press on ^6") }
        let deadline = hostNow() + 5
        while label("Flashing") != nil {
            if hostNow() > deadline { fail("the Flash timer never fired") }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            view.applyLatestFrame()
        }
        // endregion: fixture-selftest-timer

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

        // The Passcode field (^9) is secure: bullets in the frame, an AXSecureTextField with no
        // value, and Enter clears it (its request is redacted; nothing listens at its URL).
        need("^9").setAccessibilityFocused(true)
        f = settle()
        if f.textInput?.control.label != "^9" || f.textInput?.secure != true { fail("^9 is not a focused secure field") }
        type("hunter2")
        f = settle()
        expect("^9 frame text", f.textInput?.text ?? "", String(repeating: "\u{2022}", count: 7))
        if need("^9").accessibilitySubrole() != .secureTextField { fail("^9 is not an AXSecureTextField") }
        if need("^9").accessibilityValue() != nil { fail("^9 has an accessibility value") }
        if f.ax.contains(where: { $0.value.contains("hunter2") || $0.label.contains("hunter2") }) { fail("the frame holds ^9's text") }
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        f = settle()
        expect("^9 after Enter", f.textInput?.text ?? "", "")
        if view.shadowDivergences.count != 0 { fail("text shadow diverged: \(view.shadowDivergences)") }

        // region: fixture-selftest-scroll
        // The list (^14 holds the rows, ^10): 10,000 rows of 24 to 48 points that open at the top,
        // with only rows 1 to 10 laid. A scroll of 1,616 points over it lays rows 40 to 55, and the
        // runtime keeps the first row showing (46) at the top of the box as their heights come in,
        // at offset 1,604; the app hears nothing of it. The frame has a node for each row laid,
        // draws only the five that show (rows 46 to 50), and the mirror exposes only those, under an
        // AXScrollArea.
        f = settle()
        guard let box = f.ax.first(where: { $0.role == .scrollArea }) else { fail("no scroll area in the frame") }
        expect("first row showing at the top", f.ax.first { $0.control?.claim == 10 && $0.rect.h > 0 }?.control?.label ?? "", "^10#1")
        expect("row nodes at the top", f.ax.filter { $0.control?.claim == 10 }.count, 10)
        f = settle(engine.send([.scroll(center(box.rect), dx: 0, dy: 1616)]))
        expect("row nodes in the frame", f.ax.filter { $0.control?.claim == 10 }.map { $0.control!.label }, (40...55).map { "^10#\($0)" })
        guard let area = elements().first(where: { $0.accessibilityRole() == .scrollArea }) else { fail("no AXScrollArea") }
        let shown = (area.accessibilityChildren() ?? []).compactMap { ($0 as? NSAccessibilityElement)?.accessibilityIdentifier() }
        expect("rows exposed", shown, (46...50).map { "^10#\($0)" })
        if !ids("^10#").allSatisfy(shown.contains) { fail("a scrolled-out row is exposed: \(ids("^10#"))") }
        let rowTexts = f.draws.filter { if case .text(_, _, _, let t) = $0 { return t.hasPrefix("Row ") } else { return false } }
        expect("row texts drawn", rowTexts.count, 5)
        guard let r46 = f.ax.first(where: { $0.control?.label == "^10#46" }) else { fail("^10#46 not in frame") }
        expect("^10#46 at the top of the box", r46.rect.y, box.rect.y)
        // Row 50 shows only its top 16 points: a click at their centre selects it, and it grows to
        // 72 points under row 49, which stays where it was.
        guard let r50 = f.ax.first(where: { $0.control?.label == "^10#50" }) else { fail("^10#50 not in frame") }
        expect("^10#50's visible height", r50.rect.h, 16)
        f = settle(engine.send(click(center(r50.rect))))
        expect("^10#50 selected", f.ax.first { $0.control?.label == "^10#50" }?.selected ?? false, true)
        expect("^10#46 still at the top", f.ax.first { $0.control?.label == "^10#46" }?.rect.y ?? -1, box.rect.y)
        // An accessibility press is a click at the centre of the node's visible rect, through Lean.
        press("^10#48")
        f = settle()
        expect("^10#48 selected", f.ax.first { $0.control?.label == "^10#48" }?.selected ?? false, true)
        // A row added at the top (^17) leaves every row on screen where it was.
        let before = f.ax.filter { $0.control?.claim == 10 && $0.rect.h > 0 }.map { "\($0.control!.label)@\($0.rect.y)" }
        press("^17")
        f = settle()
        expect("rows on screen after Add above", f.ax.filter { $0.control?.claim == 10 && $0.rect.h > 0 }.map { "\($0.control!.label)@\($0.rect.y)" }, before)
        // endregion: fixture-selftest-scroll

        engine.stop()
        print("selftest: PASS (Fixture: focus, type, Enter, Add, toggle, delete, timer, Tab, AX, paint, secure field, virtual list)")
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

/// Offscreen renders of the virtual list (^14) through the real engine: at the top, after a
/// scroll of 1,616 points over it, with row 47 selected (72 points high), and after a scroll to the
/// end of its 10,000 rows, where the end line (^16) has heard `appear`. PNGs at 2×, no window.
@MainActor
enum ScrollShots {
    static func run(_ dir: String) {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(fixture) }
        engine.start()
        guard var f = engine.wait(through: 0)?.frame else { fail("no first frame") }
        guard let box = f.ax.first(where: { $0.role == .scrollArea })?.rect else { fail("no scroll area") }
        let renderer = try! Renderer()
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
            try! renderer.image(f, scale: 2).writePNG(to: url)
            print(url.path)
        }
        shot("scroll-top")
        f = engine.wait(through: engine.send([.pointerMove(center(box)), .scroll(center(box), dx: 0, dy: 1616)]))!.frame
        shot("scroll-1616")
        if let r = f.ax.first(where: { $0.control?.label == "^10#47" })?.rect {
            f = engine.wait(through: engine.send(click(center(r))))!.frame
            shot("scroll-selected")
        }
        f = engine.wait(through: engine.send([.scroll(center(box), dx: 0, dy: 10_000_000)]))!.frame
        shot("scroll-end")
        engine.stop()
    }
}

/// The server `--like-frames` talks to, in place of the network: post 3 refuses every write
/// (403), post 4's first write is applied but its reply lost, the rest are accepted. Every
/// answer takes 700 ms. Media only; `cairn fuzz`'s server (lean/Fixture/Fuzz.lean) is the one
/// the claims are checked against.
final class LikeServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var liked: [Int: Bool] = [:]
    nonisolated(unsafe) static var others: [Int: Int] = [1: 12, 2: 4, 3: 27, 4: 8]
    nonisolated(unsafe) static var lostOnce = false
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let k = Int(url.lastPathComponent) ?? 0
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        let method = request.httpMethod ?? "GET"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { [self] in
            LikeServer.lock.lock()
            var status = 200
            var out = ""
            var lose = false
            if method == "PUT" {
                if k == 3 {
                    status = 403
                } else {
                    LikeServer.liked[k] = body == "1"
                    if k == 4 && !LikeServer.lostOnce { LikeServer.lostOnce = true; lose = true }
                }
            } else if url.path.hasPrefix("/view/") {
                let l = LikeServer.liked[k] ?? false
                out = "\((LikeServer.others[k] ?? 0) + (l ? 1 : 0)) \(l ? 1 : 0)"
            } else {
                out = (LikeServer.liked[k] ?? false) ? "1" : "0"
            }
            LikeServer.lock.unlock()
            if lose {
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost))
                return
            }
            let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(out.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

/// `--like-frames <dir>`: the fixture against `LikeServer`, offscreen, a PNG every 1/30 s while
/// a script presses the Like buttons. `ffmpeg -framerate 30 -i <dir>/%04d.png` makes the video.
@MainActor
enum LikeFrames {
    static func run(_ dir: String) {
        var devices = Devices.inert
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [LikeServer.self]
        devices.session = URLSession(configuration: c)
        let engine = Engine(size: size, scalePercent: 200, world: World(devices: devices)) { LeanCore(fixture) }
        engine.start()
        guard var f = engine.wait(through: 0)?.frame else { fail("no first frame") }
        let renderer = try! Renderer()
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func press(_ label: String) {
            guard let r = f.ax.first(where: { $0.control?.label == label })?.rect else { fail("no \(label)") }
            engine.send([.pointerMove(center(r))] + click(center(r)))
        }
        // Seconds into the video, and the control pressed then.
        let script: [(Double, String)] = [
            (0.6, "^23"),                  // Refresh: the counts arrive
            (2.0, "^21#1"),               // like post 1: accepted
            (4.0, "^21#3"),               // like post 3: refused, rolled back with a line
            (6.6, "^21#4"),               // like post 4: the reply is lost, read back, kept
            (9.6, "^21#2"), (9.9, "^21#2"),  // post 2 twice: one write, then the second
            (12.0, "^21#3"),              // post 3 again: refused again
        ]
        var next = 0
        let start = hostNow()
        for i in 0..<(15 * 30) {
            let t = Double(i) / 30
            while hostNow() - start < t { usleep(1000) }
            while next < script.count && script[next].0 <= t { press(script[next].1); next += 1 }
            if let p = engine.latest { f = p.frame }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%04d.png", i))
            try! renderer.image(f, scale: 2).writePNG(to: url)
        }
        engine.stop()
        print(dir)
    }
}

if let i = args.firstIndex(of: "--like-frames"), i + 1 < args.count {
    MainActor.assumeIsolated { LikeFrames.run(args[i + 1]) }
    exit(0)
}

if let i = args.firstIndex(of: "--scroll-shots"), i + 1 < args.count {
    MainActor.assumeIsolated { ScrollShots.run(args[i + 1]) }
    exit(0)
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

// region: fixture-main
MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Fixture", size: size) { LeanCore(fixture) })
}
// endregion: fixture-main
