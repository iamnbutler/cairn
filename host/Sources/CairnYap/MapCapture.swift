import AppKit
import CairnCapture
import CairnFrame
import CairnHost
import CairnRender
import Foundation

/// `CairnYap --map-capture <script.json> <out dir>`: the map's captures of Yap (docs/map.md,
/// "Surfaces"). Yap has no window: what a person sees is its status item's menu and its overlay
/// panel, so each sequence runs the app on the host's real threads with its surfaces detached,
/// in the self test's world of fakes (a scratch home, a fake key and microphone, a fake typist
/// and OpenAI), and `SurfaceCapture` draws each frame: the menu from the `NSMenu` the host built,
/// and the panel through the renderer. Nothing records, listens to the real key, types into
/// another app, reaches the network, touches the clipboard or the real
/// ~/Library/Application Support/yap, or is put on screen.
///
/// The script's sequences press menu items as the conformance driver does (the item's action
/// through `performActionForItem`) and the status item by opening and closing its menu. A
/// sequence that presses a Grant item runs with both permissions denied, the only states that
/// show them. One more sequence, `overlay`, dictates with the fake key and microphone, so the
/// panel is seen recording, transcribing and typed.
@MainActor
enum YapMapCapture {
    static let menuPlace: UInt32 = 301
    static let panelPlace: UInt32 = 399
    static let f13: UInt16 = 105

    static let places: [UInt32: String] = [
        301: "The status item and its menu as the host built them from the app's frame, drawn by the capture from that `NSMenu` (titles, greyed items, checkmarks, shortcuts, submenus cascaded open), with a fake world after launch. Not a screenshot of AppKit's menu.",
        399: "The panel rendered offscreen by the app's renderer from its frame, while a fake key and microphone hold a dictation (no real key, audio or typing).",
    ]

    /// OpenAI held until the capture lets it answer, so the panel can be seen transcribing.
    final class HeldOpenAI: URLProtocol, @unchecked Sendable {
        static let open = Locked(false)
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            DispatchQueue.global().async { [self] in
                while !Self.open.value { usleep(5_000) }
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"text":"ship the map for Yap today"}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }

    /// One run of the app in a fresh scratch home.
    @MainActor final class Session {
        let home: String
        let mic = FakeMic(), keys = FakeKeys(), log = Log()
        let engine: Engine
        let view: HostView
        let host: SurfaceHost
        let panels: Renderer

        init(_ n: Int, permitted: Bool) throws {
            home = NSTemporaryDirectory() + "cairn-yap-map-\(getpid())-\(n)"
            let support = home + "/Library/Application Support/yap"
            let days = support + "/transcripts"
            try FileManager.default.createDirectory(atPath: days, withIntermediateDirectories: true)
            try #"{"keepTranscripts":true,"key":"f13","overlay":true,"retentionDays":7}"#
                .write(toFile: support + "/config.json", atomically: true, encoding: .utf8)
            try "Kubernetes\nkubernetes => Kubernetes\n".write(toFile: support + "/dictionary.txt", atomically: true, encoding: .utf8)
            // Two transcripts from earlier today, so Recent Transcripts and Copy Last have some.
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            let iso = ISO8601DateFormatter()
            let now = Date()
            let lines = [
                #"{"app":"Notes","date":"\#(iso.string(from: now.addingTimeInterval(-3600)))","text":"Pick up the proofs where we left them.","typed":true}"#,
                #"{"app":"Mail","date":"\#(iso.string(from: now.addingTimeInterval(-600)))","text":"The overlay never takes focus.","typed":true}"#,
            ]
            try (lines.joined(separator: "\n") + "\n").write(toFile: days + "/\(day.string(from: now)).jsonl", atomically: true, encoding: .utf8)

            let world = fakeWorld(home: home, mic: mic, keys: keys, log: log, protocolClass: HeldOpenAI.self, permitted: permitted)
            engine = Engine(size: size, scalePercent: 200, world: world) { LeanCore(yap) }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
            host = SurfaceHost(engine: engine, mode: .detached) { NullRenderer() }
            panels = try Renderer()
            panels.clearColor = Color(r: 0, g: 0, b: 0, a: 0)
            view.onApply = { [host] f in host.apply(f) }
            // Every effect stays here: no clipboard write, beep or quit reaches the machine.
            view.effectHook = { _ in true }
            engine.start()
            guard engine.wait(through: 0) != nil else { throw CocoaError(.featureUnsupported) }
            view.applyLatestFrame()
        }

        var frame: Frame { engine.latest!.frame }
        var menu: MenuHost? { host.menu(menuPlace) }

        /// Waits up to `timeout` s for `ok`, applying frames as they come.
        func until(_ what: String, timeout: Double = 5, _ ok: () -> Bool) throws {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while true {
                view.applyLatestFrame()
                if ok() { return }
                if Date() > deadline { throw Failure(what) }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
            }
        }

        /// Waits until no new frame has come for `quiet` s (launch's reads, a press's replies).
        func settle(quiet: Double = 0.3, timeout: Double = 5) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            var last = engine.latest?.frame, since = Date()
            while Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                view.applyLatestFrame()
                let f = engine.latest?.frame
                if f != last { last = f; since = Date() } else if Date().timeIntervalSince(since) >= quiet { return }
            }
        }

        func shot() throws -> SurfaceCapture.Shot {
            view.applyLatestFrame()
            let f = frame
            return try SurfaceCapture.draw(f, menu: { host.menu($0)?.root }, scale: 2) { s in
                let canvas = Frame(size: s.canvas.size, draws: s.canvas.draws)
                return try panels.image(canvas, scale: 2).cgImage()
            }
        }

        func stop() {
            engine.stop()
            try? FileManager.default.removeItem(atPath: home)
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ s: String) { description = s }
    }

    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 2 else {
            FileHandle.standardError.write("usage: CairnYap --map-capture <script.json> <out dir>\n".data(using: .utf8)!)
            return 2
        }
        _ = NSApplication.shared
        do {
            let (scale, sequences) = try SurfaceCapture.script(at: args[0])
            var runs: [(name: String, shots: [SurfaceCapture.Shot], steps: [SurfaceCapture.Outcome])] = []
            for (n, seq) in sequences.enumerated() {
                let s = try Session(n, permitted: !seq.steps.contains { $0.claim == 310 })
                defer { s.stop() }
                try s.until("launch: the menu never filled") { s.menu?.find("^342") != nil }
                s.settle()
                if seq.steps.contains(where: { $0.claim == 343 }) {
                    // The microphone warning shows once a recording is refused: the fake
                    // microphone refuses the next one, and the fake key starts it.
                    try s.until("launch: the key is never watched") { s.keys.listening }
                    s.mic.failNext = ReplyError(.denied, "the capture's microphone refuses")
                    s.keys.send(.keyDown, f13)
                    s.keys.send(.keyUp, f13)
                    try s.until("no microphone warning") { s.menu?.find("^343") != nil }
                    s.settle()
                }
                var shots = [try s.shot()]
                var steps: [SurfaceCapture.Outcome] = []
                for step in seq.steps {
                    guard let m = s.menu else { throw Failure("no menu") }
                    let before = s.frame
                    guard step.trigger == "press" else { steps.append(.init(step, "unsupported")); break }
                    if step.ref == before.surface(menuPlace)?.status.control {
                        m.menuWillOpen(m.root)
                        m.menuDidClose(m.root)
                    } else if let (menu, i) = m.find(step.ref.label), let item = menu.item(at: i),
                              item.action != nil, item.isEnabled {
                        menu.performActionForItem(at: i)
                    } else {
                        steps.append(.init(step, "absent"))
                        break
                    }
                    _ = s.engine.wait(through: m.lastSeq)
                    s.settle()
                    steps.append(.init(step, s.frame == before ? "inert" : "ok"))
                    shots.append(try s.shot())
                }
                runs.append((seq.name, shots, steps))
                print("\(seq.name): \(steps.map { "\($0.step.ref.label) \($0.outcome)" }.joined(separator: ", "))")
            }
            runs.append(try overlay(sequences.count))
            try SurfaceCapture.write(runs, scale: scale, places: places, out: URL(fileURLWithPath: args[1], isDirectory: true))
            return 0
        } catch {
            FileHandle.standardError.write("map capture: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }

    /// A dictation, held: the key down with speech, the key up while OpenAI is held, then the
    /// reply and the text typed (by the fake typist).
    static func overlay(_ n: Int) throws -> (name: String, shots: [SurfaceCapture.Shot], steps: [SurfaceCapture.Outcome]) {
        HeldOpenAI.open.value = false
        let s = try Session(n, permitted: true)
        defer { s.stop(); HeldOpenAI.open.value = true }
        try s.until("launch: the key is never watched") { s.keys.listening }
        s.settle()
        func texts() -> [String] {
            s.frame.surface(panelPlace)?.canvas.draws.compactMap { if case let .text(_, _, _, t) = $0 { t } else { nil } } ?? []
        }
        var shots = [try s.shot()]
        var steps: [SurfaceCapture.Outcome] = []
        func step(_ what: String) -> SurfaceCapture.Outcome { .init(.init(trigger: what, claim: 0, key: 0), "ok") }

        s.keys.send(.keyDown, f13)
        try s.until("the microphone never started") { s.mic.live }
        try s.until("the overlay never showed") { s.frame.surface(panelPlace)?.shown == true }
        for _ in 0..<12 { s.mic.push(ms: 100, amplitude: 9000); usleep(100_000); s.view.applyLatestFrame() }
        try s.until("no levels on the tape") {
            s.frame.surface(panelPlace)?.canvas.draws.contains {
                if case let .paint(_, p) = $0 { p.arrays.count == 3 && p.arrays[1].contains { $0 > 100_000 } } else { false }
            } == true
        }
        steps.append(step("hold the key and speak"))
        shots.append(try s.shot())

        s.keys.send(.keyUp, f13)
        try s.until("never transcribing: \(texts())") { texts().contains("TRANSCRIBING") }
        steps.append(step("release the key"))
        shots.append(try s.shot())

        HeldOpenAI.open.value = true
        try s.until("never typed: \(texts())") { texts().contains("TYPED") }
        try s.until("no text in the overlay: \(texts())") { texts().contains { $0.contains("Yap today") } }
        steps.append(step("the transcript is typed"))
        shots.append(try s.shot())
        print("overlay: \(steps.count) steps; typed \(s.log.typed.value)")
        return ("overlay", shots, steps)
    }
}
