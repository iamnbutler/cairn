import AppKit
import CairnFrame
import CairnHost
import os

// Bench modes for Instruments (tools/bench/yap-instruments.sh, bench/yap-instruments.md).
//
// The app as a person runs it: CairnApp.main, the status item in the menu bar, the overlay
// panel on screen drawn by MetalRenderer on its own render thread, the Lean thread and the
// world's queue. Only the devices are fakes (main.swift's `fakeWorld`, files under a scratch
// home): the microphone is fed a synthetic voice in real time through the real `record`
// subscription and `receive`; the key is pressed by the bench at the KeySource boundary (just
// after the NSEvent monitor); OpenAI is a URLProtocol stub that answers at once; typing is a
// stub that marks the moment the app would post its first key event.
//
// Nothing here times anything. The bench emits os_signposts (subsystem dev.yap.bench) and
// Instruments timestamps them. The same driver, voice and stub are in the original Yap's bench
// patch (tools/bench/yap-ref.patch), so both apps get the same input.
//
//   --bench-overlay [--seconds 20] [--buffer-ms 20] [--screen I]
//        tap (hands free), feed the voice for `seconds` in `buffer-ms` buffers, tap to send,
//        wait for TYPED to hide, exit
//   --bench-latency [--trials 21]
//        per trial: key down, 1 s of voice, key up (signpost begin), stubbed typing (end)
//   --bench-idle     launch and sit in the menu bar
//   --bench-menu     launch, then open the status item's menu after 3 s and leave it open
//   --bench-demo     for a demo video (docs/media.md): hold the key, feed the voice for 8.4 s
//        (two cuts, so a two-line preview), release; the transcription answers after 1.4 s
//        with the whole sentence, it is typed (the stub) and the overlay hides. Prints the
//        panel's window number ("demo: panel window N") so `record --window N` can take it.

let benchLog = OSLog(subsystem: "dev.yap.bench", category: "bench")

/// The synthetic voice: Yap's `Overlay.demo()` level (syllables, a pause every 3.2 s) as a
/// ±amplitude square wave at 16 kHz, so its RMS is the level × 12000.
enum BenchVoice {
    static func level(_ t: Double) -> Double {
        let phrase = t.truncatingRemainder(dividingBy: 3.2)
        guard phrase < 2.5 else { return 0.02 }
        let syllables = abs(sin(t * 9)) * (0.55 + 0.45 * sin(t * 1.7))
        return min(1, 0.15 + syllables * 0.8)
    }

    static func samples(from start: Int, count: Int) -> [Int16] {
        (0..<count).map { j in
            let n = start + j
            let a = Int16(level(Double(n) / 16000) * 12000)
            return n % 2 == 0 ? a : -a
        }
    }
}

/// OpenAI as the demo plays it: each preview chunk answers with the next phrase at once; once
/// `final` is set (the key is up), the recording's transcription answers after `delay` with
/// the whole sentence, so TRANSCRIBING stays on screen long enough to see. No network.
final class DemoOpenAI: URLProtocol, @unchecked Sendable {
    static let phrases = [
        "So the overlay should feel like a little tape machine,",
        "with the reel turning while I talk.",
    ]
    static let sentence = "So the overlay should feel like a little tape machine, with the reel turning while I talk."
    static let count = Locked(0)
    static let final = Locked(false)
    static let delay = 1.4

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var n = 0
        Self.count.update { n = $0; $0 += 1 }
        let last = Self.final.value
        let text = last ? Self.sentence : Self.phrases[min(n, Self.phrases.count - 1)]
        let answer: @Sendable () -> Void = { [self] in
            let json = try! JSONSerialization.data(withJSONObject: ["text": text])
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: json)
            client?.urlProtocolDidFinishLoading(self)
        }
        if last { DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: answer) } else { answer() }
    }
    override func stopLoading() {}
}

/// OpenAI as the bench plays it: every transcription answers at once with the next phrase.
final class BenchOpenAI: URLProtocol, @unchecked Sendable {
    static let phrases = [
        "So the overlay should feel like a little tape machine,",
        "with the reel turning while I talk",
        "and an orange mark on the tape wherever a phrase was cut.",
    ]
    static let count = Locked(0)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var n = 0
        Self.count.update { n = $0; $0 += 1 }
        let text = Self.phrases[n % Self.phrases.count]
        let json = try! JSONSerialization.data(withJSONObject: ["text": text])
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
enum Bench {
    enum Kind { case overlay, latency, idle, menu, demo }

    struct Mode {
        var kind: Kind
        var seconds = 20.0
        var bufferMs = 20
        var trials = 21
        var screen: Int?

        init?(_ args: [String]) {
            if args.contains("--bench-overlay") { kind = .overlay }
            else if args.contains("--bench-latency") { kind = .latency }
            else if args.contains("--bench-idle") { kind = .idle }
            else if args.contains("--bench-menu") { kind = .menu }
            else if args.contains("--bench-demo") { kind = .demo }
            else { return nil }
            func value(_ flag: String) -> String? {
                args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            }
            if let v = value("--seconds").flatMap(Double.init) { seconds = v }
            if let v = value("--buffer-ms").flatMap(Int.init), v >= 20, v % 20 == 0 { bufferMs = v }
            if let v = value("--trials").flatMap(Int.init) { trials = v }
            screen = value("--screen").flatMap(Int.init)
        }
    }

    static func run(_ mode: Mode) -> Never {
        PanelHost.benchScreen = mode.screen
        let home = NSTemporaryDirectory() + "cairn-yap-bench-\(getpid())"
        let support = home + "/Library/Application Support/yap"
        try! FileManager.default.createDirectory(atPath: support + "/transcripts", withIntermediateDirectories: true)
        // The original's defaults: Right Command is replaced by F13 only because the bench never
        // presses a real key; keep transcripts for 30 days; the overlay on; no dictionary.
        try! #"{"keepTranscripts":true,"key":"f13","overlay":true,"retentionDays":30}"#
            .write(toFile: support + "/config.json", atomically: true, encoding: .utf8)
        try! "".write(toFile: support + "/dictionary.txt", atomically: true, encoding: .utf8)

        let mic = FakeMic(), keys = FakeKeys(), log = Log()
        let trial = Locked(0), typed = Locked(0)
        // Typing as if the target app were already in front: the same main-thread hops as
        // `Typist.live` (exists, isActive), then the signpost where the first key event would be
        // posted.
        let typist = Typist(
            trusted: { true },
            exists: { _ in DispatchQueue.main.sync { NSRunningApplication(processIdentifier: getpid()) != nil } },
            activate: { _, _ in DispatchQueue.main.sync { NSRunningApplication(processIdentifier: getpid()) != nil } },
            post: { _, _ in
                os_signpost(.end, log: benchLog, name: "keyUpToTyped", signpostID: OSSignpostID(UInt64(trial.value)))
                typed.update { $0 += 1 }
            })
        let world = fakeWorld(home: home, mic: mic, keys: keys, log: log, typist: typist, protocolClass: mode.kind == .demo ? DemoOpenAI.self : BenchOpenAI.self)
        world.watchPeriodMs = World.liveWatchPeriodMs  // the live world's period, not the self test's

        let d = BenchDriver(mic: mic, keys: keys, typed: typed, trial: trial)
        let driver = Thread { [d] in
            let f13: UInt16 = 105, mic = d.mic, keys = d.keys, typed = d.typed, trial = d.trial
            func wait(_ what: String, _ timeout: Double = 20, _ ok: () -> Bool) { BenchDriver.wait(what, timeout, ok) }
            wait("the key is never watched") { keys.listening }
            os_signpost(.event, log: benchLog, name: "ready")  // the key is watched: ready to dictate
            usleep(1_000_000)
            switch mode.kind {
            case .overlay:
                // Tap: hands free. The voice starts as soon as the microphone does.
                os_signpost(.event, log: benchLog, name: "tap")
                keys.send(.keyDown, f13)
                wait("no microphone") { mic.live }
                let feeder = Thread { d.feed(seconds: mode.seconds, bufferMs: mode.bufferMs) }
                os_signpost(.begin, log: benchLog, name: "levels")
                feeder.start()
                usleep(100_000)
                keys.send(.keyUp, f13)
                usleep(UInt32(mode.seconds * 1_000_000))
                os_signpost(.end, log: benchLog, name: "levels")
                // Tap again: send, transcribing, typed, hidden 1.5 s later.
                os_signpost(.event, log: benchLog, name: "tap")
                keys.send(.keyDown, f13)
                keys.send(.keyUp, f13)
                wait("never typed", 10) { typed.value > 0 }
                usleep(2_500_000)
            case .latency:
                for t in 1...max(1, mode.trials) {
                    trial.value = t
                    let before = typed.value
                    keys.send(.keyDown, f13)
                    wait("no microphone") { mic.live }
                    d.feed(seconds: 1.0, bufferMs: 20)
                    os_signpost(.begin, log: benchLog, name: "keyUpToTyped", signpostID: OSSignpostID(UInt64(t)))
                    keys.send(.keyUp, f13)
                    wait("trial \(t) never typed", 10) { typed.value > before }
                    wait("the microphone stayed on") { !mic.live }
                    usleep(2_500_000)  // the overlay hides 1.5 s after TYPED
                }
            case .demo:
                // Hold: REC. The voice starts in one of its pauses, so the first 0.7 s is quiet
                // while the recorder finds the panel; cuts land about 3.2 s and 7 s in, so the
                // two-line preview shows for a second before the key comes up.
                keys.send(.keyDown, f13)
                wait("no microphone") { mic.live }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let p = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
                            print("demo: panel window \(p.windowNumber)"); fflush(stdout)
                        }
                    }
                }
                d.feed(seconds: 8.4, bufferMs: 20, from: 2.5)
                DemoOpenAI.final.value = true
                keys.send(.keyUp, f13)
                wait("never typed", 10) { typed.value > 0 }
                usleep(2_500_000)
            case .idle:
                return
            case .menu:
                usleep(2_000_000)
                DispatchQueue.main.async {
                    os_signpost(.event, log: benchLog, name: "menuOpen")
                    if !MainActor.assumeIsolated({ Bench.openStatusMenu() }) { fail("bench: no status item button") }
                }
                return
            }
            print("bench: done; \(BenchOpenAI.count.value) transcription requests, \(typed.value) typed")
            try? FileManager.default.removeItem(atPath: home)
            exit(0)
        }
        driver.qualityOfService = .userInitiated
        driver.start()

        CairnApp.main(CairnApp.Config(title: "Yap (Cairn)", size: size, makeWorld: { _ in world }) { LeanCore(yap) })
    }

    /// Clicks this app's own status item button, which opens its menu (and blocks the main
    /// thread in menu tracking until the menu closes, as a person's click does).
    static func openStatusMenu() -> Bool {
        func button(_ v: NSView?) -> NSButton? {
            guard let v else { return nil }
            if let b = v as? NSButton { return b }
            for s in v.subviews { if let b = button(s) { return b } }
            return nil
        }
        for w in NSApp.windows where String(describing: type(of: w)).contains("StatusBar") {
            if let b = button(w.contentView) { b.performClick(nil); return true }
        }
        return false
    }
}

/// The bench's hands: the fake microphone and key, and what typing has seen.
final class BenchDriver: Sendable {
    let mic: FakeMic, keys: FakeKeys, typed: Locked<Int>, trial: Locked<Int>
    init(mic: FakeMic, keys: FakeKeys, typed: Locked<Int>, trial: Locked<Int>) {
        self.mic = mic; self.keys = keys; self.typed = typed; self.trial = trial
    }

    static func wait(_ what: String, _ timeout: Double = 20, _ ok: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !ok() {
            if Date() > deadline { fail("bench: \(what)") }
            usleep(1000)
        }
    }

    /// Feeds the voice in real time from `t0` (seconds into the voice) for `seconds`, one
    /// buffer every `bufferMs`, on absolute deadlines.
    func feed(seconds: Double, bufferMs: Int, from t0: Double = 0) {
        let per = 16 * bufferMs, n = Int(seconds * 1000) / bufferMs
        let start = DispatchTime.now().uptimeNanoseconds
        for i in 0..<n {
            let due = start + UInt64(i * bufferMs) * 1_000_000
            let now = DispatchTime.now().uptimeNanoseconds
            if due > now { usleep(UInt32((due - now) / 1000)) }
            os_signpost(.event, log: benchLog, name: "level")
            mic.push(BenchVoice.samples(from: Int(t0 * 16000) + i * per, count: per))
        }
    }
}
