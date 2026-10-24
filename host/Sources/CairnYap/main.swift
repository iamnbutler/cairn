import AppKit
import CLean
import CairnFrame
import CairnHost
import CairnYapPaint
import Metal
import QuartzCore

// Yap on Cairn (lean/Examples/Yap.lean, docs/yap.md): Yap's dictation machine as a menu bar app
// with an overlay panel. No window, so it runs as an accessory.
//   CairnYap                   the app: the key, the microphone, typing, OpenAI (Nate's to run)
//   CairnYap --selftest        a day of dictation against fakes, headless, and check it
//   CairnYap --debug-socket    driven detached through the socket (docs/conformance.md), with a
//                              world that never records, listens, types or answers
//
// Every decision is Lean's. This file only builds the world: the live one, or fakes.

let yap = LeanApp(
    module: runtime_initialize_cairn_Examples_Yap_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

/// Yap has no window; this is only the size Lean starts with.
let size = Size(w: 520, h: 200)
let args = CommandLine.arguments

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

/// A world that touches nothing and answers nothing: every request stays in flight, no
/// microphone, no keys, no typing, no network. The app stays as it starts, which is what the
/// conformance model (which hears no replies) expects of it.
func silentWorld() -> World {
    var table: [UInt8: RequestHandler] = [:]
    for k in UInt8(0)...UInt8(14) { table[k] = { _, _ in } }
    return World(handlers: Handlers(table: table), devices: .inert)
}

// The overlay's tape display: the original Yap's shader, drawn where Lean puts a `yap.tape` paint.
YapTape.register()

if let i = args.firstIndex(of: "--overlay-scenes") {
    exit(OverlayScenes.run(Array(args[(i + 1)...])))
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

// MARK: - Fakes for the self test

/// A value behind a lock.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
    func update(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}

/// A microphone the test feeds: started by the world's `record`, it delivers what `push` gives
/// it from the caller's thread. Never the real one.
final class FakeMic: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: (@Sendable (UnsafeBufferPointer<Int16>) -> Void)?
    private(set) var starts = 0
    var failNext: ReplyError?

    var microphone: Microphone {
        Microphone { [self] onSamples throws(ReplyError) in
            lock.lock()
            defer { lock.unlock() }
            if let f = failNext { failNext = nil; throw f }
            starts += 1
            sink = onSamples
            return { [self] in lock.lock(); sink = nil; lock.unlock() }
        }
    }

    var live: Bool { lock.lock(); defer { lock.unlock() }; return sink != nil }
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }

    /// `ms` of 16 kHz samples at `amplitude`, in 20 ms buffers.
    func push(ms: Int, amplitude: Int16) {
        for i in 0..<(ms / 20) {
            let b = (0..<320).map { j in (j + i) % 2 == 0 ? amplitude : -amplitude }
            lock.lock()
            b.withUnsafeBufferPointer { sink?($0) }
            lock.unlock()
        }
    }
}

/// The keyboard as the test plays it.
final class FakeKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (KeyEventIn) -> Void)?
    var source: KeySource {
        KeySource(trusted: { true }) { [self] h in
            lock.lock(); handler = h; lock.unlock()
            return { [self] in lock.lock(); handler = nil; lock.unlock() }
        }
    }
    var listening: Bool { lock.lock(); defer { lock.unlock() }; return handler != nil }
    func send(_ kind: KeyEventIn.Kind, _ code: UInt16) {
        lock.lock(); let h = handler; lock.unlock()
        h?(KeyEventIn(kind: kind, keyCode: code, flags: 0, isRepeat: false, t: HostClock.monoMs()))
    }
}

/// OpenAI as the test plays it: answers each transcription with `answer`, and records what it
/// was sent.
final class FakeOpenAI: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answer = (200, #"{"text":"hello kubernetes"}"#)
    static let seen = Locked<[(url: String, auth: String, body: [UInt8])]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = [UInt8](request.httpBody ?? Data())
        if body.isEmpty, let s = request.httpBodyStream {
            s.open()
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = s.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body += buf[0..<n]
            }
            s.close()
        }
        Self.seen.update {
            $0.append((request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization") ?? "", body))
        }
        let (status, text) = Self.answer
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// What the self test's world was asked to do that would reach the person: opened, played,
/// typed.
final class Log: @unchecked Sendable {
    let opened = Locked<[String]>([])
    let sounds = Locked<[String]>([])
    let typed = Locked<[String]>([])
    let originalRunning = Locked(false)
    let typingWorks = Locked(true)
}

/// The self test's world: files under a scratch home, the fakes above, and every request that
/// would reach outside answered by the test.
func fakeWorld(home: String, mic: FakeMic, keys: FakeKeys, log: Log) -> World {
    @Sendable func moved(_ p: String) -> String { p.hasPrefix("~/") ? home + String(p.dropFirst(1)) : p }
    var h = Handlers.standard
    h.table[0] = { r, reply in if case let .readFile(p) = r { reply(Files.read(moved(p))) } }
    h.table[1] = { r, reply in if case let .writeFile(p, d) = r { reply(Files.write(moved(p), d)) } }
    h.table[2] = { r, reply in if case let .playSound(n) = r { log.sounds.update { $0.append(n) }; reply(.done) } }
    h.table[3] = { _, reply in reply(.failed(.invalid, "no http in the self test")) }
    h.table[4] = { r, reply in if case let .appendFile(p, d) = r { reply(Files.append(moved(p), d)) } }
    h.table[5] = { r, reply in if case let .listDir(p) = r { reply(Files.list(moved(p))) } }
    h.table[6] = { r, reply in if case let .deleteFile(p) = r { reply(Files.delete(moved(p))) } }
    h.table[7] = { _, reply in reply(.app(pid: 4242, name: "Notes")) }
    h.table[8] = { _, reply in reply(.flag(true)) }
    h.table[12] = { r, reply in if case let .openItem(t) = r { log.opened.update { $0.append(t) }; reply(.done) } }
    h.table[15] = { r, reply in if case let .makeDir(p) = r { reply(Files.makeDir(moved(p))) } }
    h.table[13] = { r, reply in
        if case let .appRunning(b) = r { reply(.flag(b == "dev.yap.Yap" && log.originalRunning.value)) }
    }
    h.table[14] = { r, reply in
        if case let .readDefault(_, k) = r {
            reply(k == "model" ? .bytes(Array("gpt-4o-transcribe".utf8)) : .failed(.notFound, "no such default"))
        }
    }
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [FakeOpenAI.self]
        return URLSession(configuration: c)
    }()
    let typist = Typist(trusted: { true }, exists: { _ in true },
                        activate: { _, _ in log.typingWorks.value },
                        post: { runs, ret in
                            let s = runs.map { String(utf16CodeUnits: $0, count: $0.count) }.joined()
                            log.typed.update { $0.append(s + (ret ? "⏎" : "")) }
                        })
    let devices = Devices(microphone: mic.microphone, keys: keys.source, typist: typist,
                          secrets: SecretSource(environment: { $0 == "OPENAI_API_KEY" ? "sk-selftest" : nil },
                                                readFile: { _ in nil }),
                          session: session)
    let w = World(handlers: h, devices: devices)
    w.watchPeriodMs = 50
    w.watchPath = moved
    return w
}

// MARK: - The self test

/// A day of dictation, headless: the host's real threads, menus and panel (detached), Lean on
/// its own thread, and a world of fakes. Nothing records, listens to the keyboard, types into
/// another app, reaches OpenAI or touches the real ~/Library/Application Support/yap.
@MainActor
enum SelfTest {
    static func run() {
        _ = NSApplication.shared
        let home = NSTemporaryDirectory() + "cairn-yap-selftest-\(getpid())"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let support = home + "/Library/Application Support/yap"
        let days = support + "/transcripts"
        try! FileManager.default.createDirectory(atPath: days, withIntermediateDirectories: true)
        // F13 is the key, so the test's key codes are plain ones. The dictionary has a fix.
        try! #"{"keepTranscripts":true,"key":"f13","overlay":true,"retentionDays":7}"#
            .write(toFile: support + "/config.json", atomically: true, encoding: .utf8)
        try! "Kubernetes\nkubernetes => Kubernetes\n".write(toFile: support + "/dictionary.txt", atomically: true, encoding: .utf8)
        // An old day file for retention, and a line in it for Recent Transcripts.
        let old = #"{"app":"Notes","date":"2020-01-02T10:00:00Z","text":"from long ago","typed":true}"# + "\n"
        try! old.write(toFile: days + "/2020-01-02.jsonl", atomically: true, encoding: .utf8)

        let mic = FakeMic(), keys = FakeKeys(), log = Log()
        let f13: UInt16 = 105, c: UInt16 = 8
        let engine = Engine(size: size, scalePercent: 200, world: fakeWorld(home: home, mic: mic, keys: keys, log: log)) {
            LeanCore(yap)
        }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        let host = SurfaceHost(engine: engine, mode: .detached) { NullRenderer() }
        // Every surface update (the status item's menu and the overlay panel), timed.
        let applies = LatencyStats(), rebuilds = LatencyStats()
        view.onApply = { f in
            let a = hostNow(), before = host.menu(301)?.rebuilds ?? 0
            host.apply(f)
            let ms = (hostNow() - a) * 1000
            applies.record(.lean, ms: ms)
            if (host.menu(301)?.rebuilds ?? 0) != before { rebuilds.record(.lean, ms: ms) }
        }
        var quits = 0, clipboard: [String] = []
        view.effectHook = { e in
            if case .quit = e { quits += 1; return true }
            if case let .setClipboard(s) = e { clipboard.append(s); return true }
            return false
        }
        var t0 = hostNow()
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }
        view.applyLatestFrame()
        var frame: Frame { engine.latest!.frame }

        /// Waits up to `timeout` s for `ok`, applying frames as they come.
        func until(_ what: String, timeout: Double = 5, _ ok: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while true {
                view.applyLatestFrame()
                if ok() { return }
                if Date() > deadline { fail(what) }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
            }
        }
        if frame.windowIndex != nil { fail("Yap has a window") }
        if frame.surfaces.map(\.place) != [301, 399] { fail("surfaces \(frame.surfaces.map(\.place))") }
        guard let menu = host.menu(301) else { fail("no status item at ^301") }
        func titles(_ m: NSMenu) -> [String] { m.items.map { $0.isSeparatorItem ? "-" : $0.title } }
        func item(_ id: String) -> NSMenuItem? { menu.find(id).flatMap { $0.0.item(at: $0.1) } }
        func choose(_ id: String) {
            guard let (m, i) = menu.find(id) else { fail("no item \(id): \(titles(menu.root))") }
            m.performActionForItem(at: i)
            guard engine.wait(through: menu.lastSeq) != nil else { fail("no frame after \(id)") }
            view.applyLatestFrame()
        }
        func recent() -> [String] {
            menu.root.items.first { $0.title == "Recent Transcripts" }?.submenu.map(titles) ?? []
        }
        func overlay() -> Surface? { frame.surface(399) }
        func overlayTexts() -> [String] {
            overlay()?.canvas.draws.compactMap { if case let .text(_, _, _, s) = $0 { s } else { nil } } ?? []
        }
        func dayText() -> String {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: days)) ?? []
            return names.filter { !$0.hasPrefix("2020") }.sorted().compactMap {
                try? String(contentsOfFile: days + "/" + $0, encoding: .utf8)
            }.joined()
        }
        func ms() -> String { String(format: "%.0f ms", (hostNow() - t0) * 1000) }

        // Launch: the boot reads come back, the machine launches, reads config.json and
        // dictionary.txt, lists the days (retention) and loads Recent Transcripts.
        until("launch: the key is never watched; menu \(titles(menu.root))") { keys.listening }
        let launchMs = ms()
        let expectRoot = ["Ready. Hold F13 to dictate.", "-", "Copy Last Transcript", "Recent Transcripts", "-",
                          "Dictate with F13", "Press Return After Dictating", "Keep Transcripts (7 Days)", "-",
                          "Edit Dictionary…", "Edit Settings…", "-", "Quit Yap (Cairn)"]
        until("menu \(titles(menu.root))") { titles(menu.root).dropFirst() == expectRoot.dropFirst() }
        if item("^306")?.state != .on || item("^305")?.state != .off || item("^304")?.state != .on {
            fail("checkmarks")
        }
        if item("^342")?.keyEquivalent != "q" { fail("Quit's shortcut") }
        // Retention: the 2020 file is older than seven days and goes; Recent still read it first.
        until("retention: \(String(describing: try? FileManager.default.contentsOfDirectory(atPath: days)))") {
            !FileManager.default.fileExists(atPath: days + "/2020-01-02.jsonl")
        }

        // 1. Hold: key down, 0.6 s of speech, key up. The clip is sent, saved, then typed.
        keys.send(.keyDown, f13)
        until("the microphone never started") { mic.live }
        until("the overlay never showed") { overlay()?.shown == true }
        if !overlayTexts().contains("REC") { fail("overlay says \(overlayTexts())") }
        mic.push(ms: 600, amplitude: 8000)
        until("no levels on the tape") {
            overlay()?.canvas.draws.contains {
                if case let .paint(_, p) = $0 { p.shader == YapTape.name && p.arrays.count == 3 && p.arrays[1].contains { $0 > 100_000 } }
                else { false }
            } == true
        }
        usleep(400_000)
        t0 = hostNow()
        keys.send(.keyUp, f13)
        until("hold: nothing typed (sent \(FakeOpenAI.seen.value.count))") { !log.typed.value.isEmpty }
        let holdMs = ms()
        if log.typed.value != ["hello Kubernetes "] { fail("typed \(log.typed.value)") }
        guard let up = FakeOpenAI.seen.value.last else { fail("no upload") }
        if up.auth != "Bearer sk-selftest" || !up.url.hasSuffix("/v1/audio/transcriptions") { fail("upload to \(up.url) with \(up.auth)") }
        let body = String(decoding: up.body, as: UTF8.self)
        if !body.contains("gpt-4o-transcribe") || !body.contains("RIFF") || !body.contains("Kubernetes") {
            fail("upload body: model, WAV or prompt missing")
        }
        until("the day file: \(dayText())") { dayText().contains(#""text":"hello Kubernetes""#) && dayText().contains(#""typed":true"#) }
        until("overlay typed: \(overlayTexts())") { overlayTexts().contains("TYPED") }
        until("the overlay never hid (1.5 s)", timeout: 4) { overlay()?.shown == false }
        until("recent \(recent())") { recent().first?.hasSuffix("hello Kubernetes") == true }
        if !recent().contains(where: { $0.hasSuffix("from long ago") }) { fail("old transcript not in Recent: \(recent())") }
        if mic.live { fail("the microphone is still on") }

        // 2. Tap: under 300 ms latches hands free; a second tap sends.
        let sentBefore = FakeOpenAI.seen.value.count
        keys.send(.keyDown, f13)
        until("tap: no microphone") { mic.live }
        keys.send(.keyUp, f13)
        mic.push(ms: 600, amplitude: 6000)
        until("hands free: \(overlayTexts())") { overlayTexts().contains { $0.hasPrefix("REC · HANDS FREE") } }
        if !mic.live { fail("a tap stopped the recording") }
        keys.send(.keyDown, f13)
        keys.send(.keyUp, f13)
        until("second tap: typed \(log.typed.value)") { log.typed.value.count == 2 }
        if FakeOpenAI.seen.value.count <= sentBefore { fail("the hands-free clip was not sent") }

        // 3. Shortcut: the key plus another key cancels; nothing is sent or typed.
        let sent3 = FakeOpenAI.seen.value.count
        keys.send(.keyDown, f13)
        until("shortcut: no microphone") { mic.live }
        mic.push(ms: 600, amplitude: 8000)
        keys.send(.keyDown, c)
        usleep(400_000)
        keys.send(.keyUp, f13)
        until("shortcut: the microphone stayed on") { !mic.live }
        usleep(300_000)
        if FakeOpenAI.seen.value.count != sent3 || log.typed.value.count != 2 { fail("a shortcut sent or typed") }

        // 4. Silent clip: held long enough, but quiet: never sent.
        keys.send(.keyDown, f13)
        until("silent: no microphone") { mic.live }
        mic.push(ms: 600, amplitude: 20)
        usleep(400_000)
        keys.send(.keyUp, f13)
        until("silent: the microphone stayed on") { !mic.live }
        usleep(300_000)
        if FakeOpenAI.seen.value.count != sent3 { fail("a silent clip was sent") }

        // 5. Failed type: the app can't be brought forward. Kept in Recent with ⚠︎, Basso plays.
        log.typingWorks.value = false
        FakeOpenAI.answer = (200, #"{"text":"lost words"}"#)
        keys.send(.keyDown, f13)
        until("failed: no microphone") { mic.live }
        mic.push(ms: 600, amplitude: 8000)
        usleep(400_000)
        keys.send(.keyUp, f13)
        until("failed type: recent \(recent()), sounds \(log.sounds.value)") {
            recent().first?.contains("⚠︎ lost words") == true && log.sounds.value.contains("Basso")
        }
        until("overlay failed: \(overlayTexts())") { overlayTexts().contains("NOT TYPED · IN RECENT TRANSCRIPTS") }
        until("the failed overlay never hid (4 s)", timeout: 6) { overlay()?.shown == false }
        until("day file keeps it untyped") { dayText().contains(#""text":"lost words","typed":false"#) }
        log.typingWorks.value = true
        FakeOpenAI.answer = (200, #"{"text":"hello kubernetes"}"#)

        // Copy Last Transcript copies the failed one; a Recent item copies itself.
        choose("^302")
        if clipboard.last != "lost words" { fail("clipboard \(clipboard)") }
        choose("^303#1")
        if clipboard.last != "hello Kubernetes" { fail("clipboard \(clipboard)") }

        // 6. Live reload: config.json and dictionary.txt are read again when they change.
        try! #"{"keepTranscripts":false,"key":"f13","overlay":true,"retentionDays":7}"#
            .write(toFile: support + "/config.json", atomically: true, encoding: .utf8)
        until("config reload: Keep is \(String(describing: item("^304")?.state))") { item("^304")?.state == .off }
        try! "kubernetes => K8s\n".write(toFile: support + "/dictionary.txt", atomically: true, encoding: .utf8)
        usleep(300_000)
        let before6 = dayText()
        keys.send(.keyDown, f13)
        until("reload: no microphone") { mic.live }
        mic.push(ms: 600, amplitude: 8000)
        usleep(400_000)
        keys.send(.keyUp, f13)
        until("reloaded dictionary: typed \(log.typed.value)") { log.typed.value.last == "hello K8s " }
        usleep(200_000)
        if dayText() != before6 { fail("a transcript was saved with Keep Transcripts off") }
        // Keep Transcripts from the menu writes config.json.
        choose("^304")
        until("Keep from the menu") {
            (try? String(contentsOfFile: support + "/config.json", encoding: .utf8))?.contains(#""keepTranscripts" : true"#) == true
        }

        // 7. Press Return After Dictating.
        choose("^305")
        if item("^305")?.state != .on { fail("Press Return is not on") }
        keys.send(.keyDown, f13)
        until("return: no microphone") { mic.live }
        mic.push(ms: 600, amplitude: 8000)
        usleep(400_000)
        keys.send(.keyUp, f13)
        until("return: typed \(log.typed.value)") { log.typed.value.last == "hello K8s⏎" }
        until("prefs.json") {
            (try? String(contentsOfFile: home + "/Library/Application Support/Cairn/Yap/prefs.json", encoding: .utf8))?
                .contains(#""submits":true"#) == true
        }

        // 8. Recent holds five.
        until("recent holds five: \(recent())") { recent().count == 5 + 2 }

        // 9. The original Yap starts: the key is let go, and the menu says why.
        log.originalRunning.value = true
        until("original running: still listening", timeout: 5) { !keys.listening }
        until("menu: \(titles(menu.root))") {
            titles(menu.root).contains("Yap is running. Quit it to dictate with F13 here.")
        }
        log.originalRunning.value = false
        menu.menuWillOpen(menu.root)  // opening the menu checks again (^344)
        menu.menuDidClose(menu.root)
        until("original quit: not listening again") { keys.listening }

        // Levels at 50 Hz: a 3 s hold fed in real time, one 20 ms buffer per 20 ms, each a
        // `record` event and a Lean step that redraws the tape. Then a shortcut cancels it.
        keys.send(.keyDown, f13)
        until("levels: no microphone") { mic.live }
        until("levels: no overlay") { overlay()?.shown == true }
        engine.stats.reset()
        applies.reset()
        let v0 = engine.latest!.version, start = hostNow()
        for i in 0..<150 {
            let due = start + Double(i) * 0.02
            let wait = due - hostNow()
            if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
            mic.push(ms: 20, amplitude: Int16(2000 + (i % 25) * 300))
            view.applyLatestFrame()
        }
        let levelSecs = hostNow() - start
        let levelFrames = engine.latest!.version - v0
        let levelLean = engine.stats.summary(.lean), levelApply = applies.summary(.lean)
        keys.send(.keyDown, c)
        keys.send(.keyUp, f13)
        until("levels: the microphone stayed on") { !mic.live }

        // 10. The menu's other items open things (recorded, not opened) and Dictate turns off.
        choose("^308")
        choose("^309")
        let recentFolder = menu.root.items.first { $0.title == "Recent Transcripts" }!.submenu!
        if let i = recentFolder.items.firstIndex(where: { $0.title == "Open Transcripts Folder" }) {
            recentFolder.performActionForItem(at: i)
        } else { fail("no Open Transcripts Folder") }
        until("opened \(log.opened.value)") { log.opened.value.count == 3 }
        if !log.opened.value.contains("~/Library/Application Support/yap/dictionary.txt")
            || !log.opened.value.contains("~/Library/Application Support/yap/config.json")
            || !log.opened.value.contains("~/Library/Application Support/yap/transcripts") { fail("opened \(log.opened.value)") }
        choose("^306")
        until("Dictate off: still listening") { !keys.listening }
        if item("^305")?.isEnabled == true { fail("Press Return is enabled with Dictate off") }

        choose("^342")
        if quits != 1 { fail("Quit sent \(quits) quits") }
        engine.stop()
        print("selftest: PASS (Yap: launch, hold, tap, shortcut, silent, failed type, copy, live reload, return, recent five, original Yap, menu items, quit)")
        print("  launch to listening: \(launchMs); key up to typed (fake OpenAI): \(holdMs)")
        print(String(format: "  levels at 50 Hz: 150 buffers in %.2f s, %d frames published", levelSecs, levelFrames))
        print("  Lean step+frame+decode per batch while recording: \(levelLean)")
        print("  surface apply (menu + overlay) per frame while recording: \(levelApply)")
        print("  menu rebuilds (item shapes changed) over the whole test: \(rebuilds.summary(.lean))")
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Yap (Cairn)", size: size,
                                  makeWorld: { debug in debug ? silentWorld() : World() }) { LeanCore(yap) })
}
