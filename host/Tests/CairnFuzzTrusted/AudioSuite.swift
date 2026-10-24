import CairnFrame
import CairnHost
import Foundation

/// A microphone that plays back synthetic samples from its own thread, in buffers of random
/// sizes. Never the real one: `make check` records nothing. Starting it takes `startUs`, as
/// AVAudioEngine's `start` blocks until the engine runs; with `early`, its thread delivers
/// while `start` is still blocked (a tap can fire before `start` returns).
final class FakeMic: @unchecked Sendable {
    let buffers: [[Int16]]
    let pauseUs: UInt32
    let failure: ReplyError?
    let startUs: UInt32
    let early: Bool
    private let lock = NSLock()
    private var stopped = false
    private var running_ = false
    private(set) var delivered: [Int16] = []
    private(set) var starts = 0
    private let finished = DispatchSemaphore(value: 0)

    init(buffers: [[Int16]], pauseUs: UInt32, failure: ReplyError? = nil, startUs: UInt32 = 0, early: Bool = false) {
        self.buffers = buffers; self.pauseUs = pauseUs; self.failure = failure
        self.startUs = startUs; self.early = early
    }

    /// `start` has returned and the microphone is not stopped.
    var running: Bool { lock.lock(); defer { lock.unlock() }; return running_ }

    var microphone: Microphone {
        Microphone { [self] onSamples throws(ReplyError) in
            lock.lock(); starts += 1; lock.unlock()
            if !early, startUs > 0 { usleep(startUs) }
            if let failure { throw failure }
            defer {
                if early, startUs > 0 { usleep(startUs) }
                lock.lock(); running_ = !stopped; lock.unlock()
            }
            Thread.detachNewThread { [self] in
                for b in buffers {
                    lock.lock()
                    if stopped { lock.unlock(); break }
                    // Delivered under the lock, so a stop that has returned has no buffer still
                    // being delivered (the contract `Microphone.start` states).
                    delivered += b
                    b.withUnsafeBufferPointer { onSamples($0) }
                    lock.unlock()
                    if pauseUs > 0 { usleep(pauseUs) }
                }
                finished.signal()
            }
            return { [self] in
                lock.lock(); stopped = true; running_ = false; lock.unlock()
            }
        }
    }

    var samples: [Int16] { lock.lock(); defer { lock.unlock() }; return delivered }
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    func waitDone(_ s: Double) -> Bool { finished.wait(timeout: .now() + s) == .success }
}

/// `record`, its levels, and the WAV files cut from clips:
///
/// - `subs.record`: with a fake microphone delivering synthetic buffers from another thread,
///   the clip holds exactly the samples delivered; the audio events cover a prefix of them in
///   order, each event's frames and peak are its batch's, and their windows are the oracle's
///   20 ms levels of that prefix; nothing is sent after the stop or reset returns; a microphone
///   that fails is one `failed` event with its fault and an empty finished clip. The level
///   meter gives the same windows however the samples are split.
/// - `subs.record-start`: with a fake microphone that takes a while to start (delivering while
///   it starts, or not), the subscription's first event is one `started`, sent only once the
///   microphone's `start` has returned, and before every `audio`; there is no other `started`;
///   a microphone that fails to start sends `failed` and never `started`.
/// - `effects.clip-wav`: `wav` of windows s..<e is a RIFF/WAVE header (checked field by field)
///   and exactly those samples; to the end includes a partial window; a clip still recording is
///   waited for; past the end or backwards is `invalid`, unknown `notFound`; `forgetClip`
///   answers done then notFound; at most 8 clips are kept, never dropping the newest.
final class AudioSuite: Suite {
    let name = "audio"
    let crashCheck = "subs.record"
    let checks: [String: CheckInfo] = [
        "subs.record": CheckInfo(
            title: "`record` streams the levels of exactly the samples it keeps, and nothing after its stop",
            trusted: ["host/Sources/CairnHost/World.swift (record)", "AudioEffects.swift (LevelMeter, Clips)"],
            oracle: "a fake microphone's delivered samples and levels computed from them directly"),
        "subs.record-start": CheckInfo(
            title: "`record` reports `started` once its microphone is running, before any audio, or fails without it",
            trusted: ["host/Sources/CairnHost/World.swift (record)"],
            oracle: "a fake microphone that blocks in `start`, sometimes delivering meanwhile, and says when `start` returned"),
        "effects.clip-wav": CheckInfo(
            title: "A clip's WAV for a range of windows holds exactly those samples",
            trusted: ["host/Sources/CairnHost/AudioEffects.swift (Clips.wav, WAV)"],
            oracle: "the RIFF/WAVE layout written out field by field, and the delivered samples"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 8) }
    func setUp() {}

    func run(_ g: inout SplitMix, _ r: Recorder) {
        meter(&g, r)
        record(&g, r)
        wav(&g, r)
        clipLimit(&g, r)
    }

    // MARK: oracle

    static func mag(_ s: Int16) -> UInt32 { s == .min ? 32767 : UInt32(abs(Int(s))) }

    static func levels(_ s: ArraySlice<Int16>) -> [Level] {
        var out: [Level] = []
        var i = s.startIndex
        while i + 320 <= s.endIndex {
            var sum: UInt64 = 0, peak: UInt32 = 0
            for x in s[i..<i + 320] { sum += UInt64(Int(x) * Int(x)); peak = max(peak, mag(x)) }
            out.append(Level(sumSq: sum, peak: peak))
            i += 320
        }
        return out
    }

    static func wavFile(_ s: ArraySlice<Int16>) -> [UInt8] {
        func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func le16(_ v: Int) -> [UInt8] { (0..<2).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let n = s.count * 2
        var out = Array("RIFF".utf8) + le32(36 + n) + Array("WAVE".utf8)
        out += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16000) + le32(32000) + le16(2) + le16(16)
        out += Array("data".utf8) + le32(n)
        for x in s { out += le16(Int(UInt16(bitPattern: x))) }
        return out
    }

    /// Synthetic audio: silence, a loud square wave, noise, and the extremes.
    static func signal(_ g: inout SplitMix, _ n: Int) -> [Int16] {
        var out: [Int16] = []
        out.reserveCapacity(n)
        while out.count < n {
            let len = min(n - out.count, g.range(1, 2000))
            switch g.below(5) {
            case 0: out += [Int16](repeating: 0, count: len)
            case 1:
                let a = Int16(g.range(1, 32767)), p = g.range(2, 80)
                out += (0..<len).map { ($0 / (p / 2 + 1)) % 2 == 0 ? a : -a }
            case 2: out += (0..<len).map { _ in Int16(truncatingIfNeeded: g.next()) }
            case 3: out += (0..<len).map { _ in g.elem([Int16.min, .max, -1, 1, 0]) }
            default: out += (0..<len).map { _ in Int16(g.range(-200, 200)) }
            }
        }
        return out
    }

    static func split(_ g: inout SplitMix, _ s: [Int16]) -> [[Int16]] {
        var out: [[Int16]] = []
        var i = 0
        while i < s.count {
            let n = min(s.count - i, g.weighted([(3, { $0.range(300, 700) }), (1, { $0.range(0, 5) }), (1, { $0.range(1, 4000) })]))
            out.append(Array(s[i..<i + n]))
            i += n
        }
        return out
    }

    // MARK: checks

    func meter(_ g: inout SplitMix, _ r: Recorder) {
        let c = "subs.record"
        let s = Self.signal(&g, g.range(0, 5000))
        var m = LevelMeter()
        var ws: [Level] = []
        for b in Self.split(&g, s) {
            let (pk, w) = m.feed(b)
            r.expect(c, pk == (b.map(Self.mag).max() ?? 0), "batch peak \(pk)")
            ws += w
        }
        r.expect(c, ws == Self.levels(s[...]), "meter windows differ from the oracle for \(s.count) samples")
        r.count(c, "meterWindows", ws.count)
    }

    func record(_ g: inout SplitMix, _ r: Recorder) {
        let c = "subs.record"
        let fail = g.chance(1, 8) ? ReplyError(g.elem([.denied, .notFound, .other]), "fake \(g.below(100))") : nil
        let samples = Self.signal(&g, g.range(0, 16000 * 2))
        let startUs = UInt32(g.elem([0, 0, 2000, 20_000]))
        let mic = FakeMic(buffers: Self.split(&g, samples), pauseUs: UInt32(g.elem([0, 100, 1000, 3000])), failure: fail,
                          startUs: startUs, early: g.chance(1, 2))
        var d = Devices.inert
        d.microphone = mic.microphone
        let world = World(handlers: Handlers(table: [:]), devices: d)
        let sent = Locked<[Event]>([])
        // Whether the microphone was running when each `started` was sent (^1005).
        let startedRunning = Locked<[Bool]>([])
        world.send = { es in
            if es.contains(where: { if case .subEvent(_, .started) = $0 { true } else { false } }) {
                startedRunning.update { $0.append(mic.running) }
            }
            sent.update { $0 += es }
        }
        let id = UInt32(g.below(5)), clip = UInt32(truncatingIfNeeded: g.next())
        world.run([], [.start(id: id, .record(clip: clip))])
        usleep(UInt32(g.elem([0, 1000, 10_000, 40_000, 100_000])))
        let reset = g.chance(1, 6)
        if reset { world.reset() } else { world.run([], [.stop(id: id)]) }
        let atStop = sent.value.count
        let got = mic.samples
        usleep(15_000)
        r.expect(c, sent.value.count == atStop, "\(sent.value.count - atStop) events after the stop returned")
        r.expect(c, mic.startCount == 1, "the microphone started \(mic.startCount) times")
        var events = sent.value
        let s = "subs.record-start"
        let starts = events.filter { if case .subEvent(_, .started) = $0 { true } else { false } }
        if let fail {
            r.expect(s, starts.isEmpty, "a microphone that failed to start sent \(starts.count) started")
            r.count(s, "failed")
            r.expect(c, events == [.subEvent(id: id, .failed(fail.fault, fail.message))], "a failing microphone sent \(events)")
            if !reset {
                if case let .success(w) = world.clips.wav(clip, start: 0, stop: nil, wait: 0) {
                    r.expect(c, w == Self.wavFile([]), "the failed clip is not empty")
                } else { r.fail(c, "no clip after a failed start") }
            }
            r.count(c, "failed")
            return
        }
        r.expect(s, events.first == .subEvent(id: id, .started), "the first event is \(String(describing: events.first)), not started")
        r.expect(s, starts.count == 1, "\(starts.count) started events")
        r.expect(s, startedRunning.value == [true], "started sent while the microphone was not running: \(startedRunning.value)")
        r.count(s, "started")
        if startUs > 0 { r.count(s, mic.early ? "slowEarly" : "slow") }
        if events.first == .subEvent(id: id, .started) { events.removeFirst() }
        var at = 0
        var windows: [Level] = []
        for e in events {
            guard case let .subEvent(eid, .audio(n, pk, ws)) = e, eid == id else { r.fail(c, "unexpected \(e)"); return }
            guard at + Int(n) <= got.count else { r.fail(c, "events count \(at + Int(n)) frames of \(got.count)"); return }
            let batch = got[at..<at + Int(n)]
            r.expect(c, pk == (batch.map(Self.mag).max() ?? 0), "event peak \(pk)")
            at += Int(n)
            windows += ws
        }
        r.expect(c, windows == Self.levels(got[0..<at]), "the windows sent are not the levels of the first \(at) samples")
        if reset {
            r.expect(c, world.clips.ids.isEmpty, "clips kept after reset")
        } else {
            switch world.clips.wav(clip, start: 0, stop: nil, wait: 0) {
            case let .success(w): r.expect(c, w == Self.wavFile(got[...]), "the clip is not the \(got.count) samples delivered")
            case let .failure(e): r.fail(c, "the clip: \(e)")
            }
        }
        r.count(c, "frames", at)
        r.count(c, "windows", windows.count)
        r.count(c, reset ? "reset" : "stopped")
    }

    func wav(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.clip-wav"
        let clips = Clips()
        let id = UInt32(g.below(4))
        let s = Self.signal(&g, g.range(0, 6000))
        clips.begin(id)
        // Sometimes the clip is still recording when asked for: it finishes from another thread.
        let late = g.chance(1, 3)
        let split = late ? g.range(0, s.count) : s.count
        s[0..<split].withUnsafeBufferPointer { _ = clips.append(id, $0) }
        if late {
            let rest = Array(s[split...])
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) {
                rest.withUnsafeBufferPointer { _ = clips.append(id, $0) }
                clips.finish(id)
            }
        } else { clips.finish(id) }
        let total = s.count / 320
        for _ in 0..<6 {
            let a = UInt32(g.range(0, total + 2)), b: UInt32? = g.chance(1, 3) ? nil : UInt32(g.range(0, total + 2))
            let got = clips.wav(id, start: a, stop: b, wait: 2)
            let lo = Int(a) * 320, hi = b.map { Int($0) * 320 } ?? s.count
            if lo <= hi, hi <= s.count {
                r.expect(c, got == .success(Self.wavFile(s[lo..<hi])), "wav \(a)..<\(String(describing: b)) of \(s.count) samples")
                r.count(c, "ranges")
            } else {
                if case .failure(let e) = got, e.fault == .invalid { r.ran(c) } else { r.fail(c, "wav \(a)..<\(String(describing: b)) of \(s.count) is not invalid") }
                r.count(c, "badRanges")
            }
        }
        if case .failure(let e) = clips.wav(id &+ 9, start: 0, stop: nil, wait: 0), e.fault == .notFound { r.ran(c) } else { r.fail(c, "unknown clip") }
        // forgetClip through the world's handler.
        let world = World(handlers: Handlers(table: [:]), devices: .inert)
        let replies = Locked<[Event]>([])
        world.send = { es in replies.update { $0 += es } }
        world.clips.begin(id)
        world.clips.finish(id)
        world.run([.request(id: 1, .forgetClip(clip: id)), ], [])
        usleep(20_000)
        world.run([.request(id: 2, .forgetClip(clip: id))], [])
        usleep(20_000)
        let rs = replies.value
        r.expect(c, rs.contains(.reply(id: 1, .done)) && rs.contains { if case .reply(2, .failed(.notFound, _)) = $0 { true } else { false } } && rs.count == 2,
                 "forgetClip twice: \(rs)")
        if case .failure(let e) = world.clips.wav(id, start: 0, stop: nil, wait: 0), e.fault == .notFound { r.ran(c) } else { r.fail(c, "a forgotten clip is still there") }
    }

    func clipLimit(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.clip-wav"
        let clips = Clips()
        var last: UInt32 = 0
        for _ in 0..<g.range(1, 20) {
            last = UInt32(g.below(30))
            clips.begin(last)
            if g.chance(2, 3) { clips.finish(last) }
            r.expect(c, clips.ids.count <= Clips.maxClips && clips.ids.contains(last), "clips \(clips.ids.sorted()) after beginning \(last)")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "level meter, record with a fake microphone, wav ranges and the clip limit"
    }
}
