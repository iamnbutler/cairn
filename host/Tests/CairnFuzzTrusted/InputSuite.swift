import CairnFrame
import CairnHost
import Foundation

/// `globalKey` and `typeText`, against stubs only: no monitor is installed and no key event is
/// posted to any app.
///
/// - `subs.global-key`: `KeyWatch` against a model of Yap's PushToTalk written as a state
///   table, over random event streams (modifier and ordinary hotkeys, repeats, other keys, flags
///   with unrelated bits); through the world with a fake key source, the events sent are the
///   model's, in order, with the events' times; nothing after the stop returns; without
///   Accessibility one `failed denied` and the source is never started; a code past 16 bits is
///   `failed invalid`.
/// - `effects.type-text`: `Typing.runs` concatenates to the text's UTF-16, each run at most 20
///   units or a single longer character, never splitting a character; with a fake typist,
///   every combination of empty text, trust, a running app and one that comes forward gives
///   the documented answer, posts only when all hold (exactly the runs, Return as asked), and
///   asks the system only what it must, in order.
final class InputSuite: Suite {
    let name = "input"
    let crashCheck = "subs.global-key"
    let checks: [String: CheckInfo] = [
        "subs.global-key": CheckInfo(
            title: "`globalKey` reports the hotkey's press and release, and other keys while it is held",
            trusted: ["host/Sources/CairnHost/InputEffects.swift (KeyWatch, KeySource)", "World.swift (globalKey)"],
            oracle: "a state-table model of Yap's PushToTalk, and a fake key source"),
        "effects.type-text": CheckInfo(
            title: "`typeText` types exactly the text into that app, or nothing",
            trusted: ["host/Sources/CairnHost/InputEffects.swift (Typing, Typist)"],
            oracle: "the text's UTF-16 and Characters; a fake typist recording each call"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 4) }
    func setUp() {}

    func run(_ g: inout SplitMix, _ r: Recorder) {
        keys(&g, r)
        typing(&g, r)
    }

    // MARK: globalKey

    /// Yap's hotkeys: the modifiers with their flags, and a few ordinary keys.
    static let hotkeys: [(UInt16, UInt?)] = [(54, 1 << 20), (55, 1 << 20), (61, 1 << 19), (58, 1 << 19), (62, 1 << 18),
                                             (60, 1 << 17), (63, 1 << 23), (105, nil), (122, nil), (0, nil)]

    static func stream(_ g: inout SplitMix, _ code: UInt16, _ flag: UInt?) -> [KeyEventIn] {
        var t = UInt64(g.below(1 << 30))
        return (0..<g.range(0, 60)).map { _ in
            t += UInt64(g.below(200))
            let kc: UInt16 = g.chance(1, 2) ? code : g.elem([54, 55, 56, 58, 61, 63, 0, 12, 36, 105, 122])
            let kind = g.elem([KeyEventIn.Kind.flagsChanged, .keyDown, .keyUp])
            var flags = UInt(g.below(1 << 24)) & ~(flag ?? 0)
            if let flag, g.bool() { flags |= flag }
            return KeyEventIn(kind: kind, keyCode: kc, flags: flags, isRepeat: kind == .keyDown && g.chance(1, 4), t: t)
        }
    }

    /// The model: what each event means, given whether the hotkey is down.
    static func model(_ code: UInt16, _ flag: UInt?, _ es: [KeyEventIn]) -> [SubEvent] {
        var down = false
        var out: [SubEvent] = []
        for e in es {
            let ours = e.keyCode == code
            var next = down
            switch (e.kind, flag) {
            case (.flagsChanged, let f?) where ours: next = e.flags & f != 0
            case (.keyDown, nil) where ours: if !e.isRepeat { next = true }
            case (.keyUp, nil) where ours: next = false
            case (.keyDown, _) where down: out.append(.otherKey(e.t))
            default: break
            }
            if next != down { out.append(next ? .keyDown(e.t) : .keyUp(e.t)); down = next }
        }
        return out
    }

    func keys(_ g: inout SplitMix, _ r: Recorder) {
        let c = "subs.global-key"
        let (code, flag) = g.elem(Self.hotkeys)
        let es = Self.stream(&g, code, flag)
        var w = KeyWatch(code: code, modifier: flag)
        let got = es.compactMap { w.handle($0) }
        let want = Self.model(code, flag, es)
        r.expect(c, got == want, "KeyWatch(\(code), \(String(describing: flag))) gave \(got), the model \(want)")
        r.count(c, "events", es.count)
        r.count(c, "reported", got.count)

        // Through the world, with a fake source fed from another thread.
        let trusted = g.chance(5, 6)
        let started = Locked(0)
        let handler = Locked<(@Sendable (KeyEventIn) -> Void)?>(nil)
        var d = Devices.inert
        d.keys = KeySource(trusted: { trusted }) { h in
            started.update { $0 += 1 }
            handler.value = h
            return { handler.value = nil }
        }
        let world = World(handlers: Handlers(table: [:]), devices: d)
        let sent = Locked<[Event]>([])
        world.send = { e in sent.update { $0 += e } }
        let id = UInt32(g.below(4))
        let big = g.chance(1, 12)
        let wcode: UInt32 = big ? UInt32(g.range(65536, Int(UInt32.max))) : UInt32(code)
        world.run([], [.start(id: id, .globalKey(code: wcode, modifier: flag.map { UInt32($0) }))])
        if big {
            usleep(2000)
            r.expect(c, started.value == 0 && sent.value.count == 1 && { if case .subEvent(id, .failed(.invalid, _)) = sent.value[0] { true } else { false } }(),
                     "code \(wcode): \(sent.value)")
            return
        }
        guard trusted else {
            usleep(2000)
            r.expect(c, started.value == 0, "the key source started without Accessibility")
            r.expect(c, sent.value.count == 1 && { if case .subEvent(id, .failed(.denied, _)) = sent.value[0] { true } else { false } }(),
                     "untrusted globalKey sent \(sent.value)")
            r.count(c, "untrusted")
            return
        }
        let feed = DispatchSemaphore(value: 0)
        let h = handler.value
        Thread.detachNewThread {
            for e in es { h?(e) }
            feed.signal()
        }
        feed.wait()
        // Every event fed has been queued; a stop on the queue comes after all of them.
        world.run([], [.stop(id: id)])
        let atStop = sent.value
        r.expect(c, atStop == want.map { .subEvent(id: id, $0) }, "the world sent \(atStop), the model \(want)")
        h?(KeyEventIn(kind: .keyDown, keyCode: code, flags: flag ?? 0, isRepeat: false, t: 1))
        usleep(5000)
        r.expect(c, sent.value.count == atStop.count, "events after the stop")
        r.expect(c, handler.value == nil && started.value == 1, "the source was not stopped once")
    }

    // MARK: typeText

    func typing(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.type-text"
        let text: String = g.weighted([
            (6, { TextPool.string(&$0) }),
            (1, { g in String(repeating: "👍🏽", count: g.range(1, 12)) }),
            (1, { g in "e" + String(repeating: "\u{301}", count: g.range(15, 30)) + "x" }),  // one long character
            (1, { _ in "" }),
        ])
        let runs = Typing.runs(of: text)
        r.expect(c, runs.flatMap { $0 } == Array(text.utf16), "runs don't concatenate to the text")
        var chars = Array(text).map { Array($0.utf16) }
        var ok = true
        for run in runs {
            // Each run is a whole number of characters, at most 20 units unless it is one.
            var take: [UInt16] = [], n = 0
            while take.count < run.count, !chars.isEmpty { take += chars.removeFirst(); n += 1 }
            if take != run || (run.count > Typing.unitsPerEvent && n != 1) || run.isEmpty { ok = false }
        }
        r.expect(c, ok && chars.isEmpty, "runs of \(text.debugDescription) split a character or are too long: \(runs.map(\.count))")

        let trusted = g.chance(4, 5), exists = g.chance(4, 5), comes = g.chance(4, 5), ret = g.bool()
        let pid = g.chance(3, 4) ? UInt32(g.range(1, Int(Int32.max))) : g.elem([UInt32(0), 1, UInt32(Int32.max), UInt32(Int32.max) + 1, .max])
        let calls = Locked<[String]>([])
        let posted = Locked<[([[UInt16]], Bool)]>([])
        let typist = Typist(
            trusted: { calls.update { $0.append("trusted") }; return trusted },
            exists: { p in calls.update { $0.append("exists \(p)") }; return exists },
            activate: { p, t in calls.update { $0.append("activate \(p) \(t)") }; return comes },
            post: { rs, rt in posted.update { $0.append((rs, rt)) } })
        let viaWorld = g.bool()
        var got: Reply
        if viaWorld {
            var d = Devices.inert
            d.typist = typist
            let world = World(handlers: Handlers(table: [:]), devices: d)
            let sent = Locked<[Event]>([])
            let done = DispatchSemaphore(value: 0)
            world.send = { e in sent.update { $0 += e }; done.signal() }
            world.run([.request(id: 7, .typeText(pid: pid, text: text, pressReturn: ret))], [])
            _ = done.wait(timeout: .now() + 2)
            guard case let .reply(7, rep)? = sent.value.first else { r.fail(c, "no reply: \(sent.value)"); return }
            got = rep
        } else {
            got = Typing.type(pid: pid, text: text, pressReturn: ret, typist)
        }
        let validPid = pid > 0 && pid <= UInt32(Int32.max)
        let want: Reply, wantCalls: [String]
        if text.isEmpty { want = .failed(.invalid, ""); wantCalls = [] }
        else if !trusted { want = .failed(.denied, ""); wantCalls = ["trusted"] }
        else if !validPid { want = .failed(.notFound, ""); wantCalls = ["trusted"] }
        else if !exists { want = .failed(.notFound, ""); wantCalls = ["trusted", "exists \(pid)"] }
        else if !comes { want = .failed(.other, ""); wantCalls = ["trusted", "exists \(pid)", "activate \(pid) 0.6"] }
        else { want = .done; wantCalls = ["trusted", "exists \(pid)", "activate \(pid) 0.6"] }
        func shape(_ x: Reply) -> String { if case let .failed(f, _) = x { "failed \(f)" } else { "\(x)" } }
        r.expect(c, shape(got) == shape(want), "typeText(\(pid), trusted \(trusted), exists \(exists), comes \(comes)) answered \(got), want \(shape(want))")
        r.expect(c, calls.value == wantCalls, "asked the system \(calls.value), want \(wantCalls)")
        let p = posted.value
        if want == .done {
            r.expect(c, p.count == 1 && p[0].0 == runs && p[0].1 == ret, "posted \(p.count) bursts")
        } else {
            r.expect(c, p.isEmpty, "posted after \(shape(want))")
        }
        let desc = DebugJSON.describe(.typeText(pid: pid, text: text, pressReturn: ret))
        r.expect(c, text.count < 4 || !desc.contains(text), "the debug description shows the typed text")
        r.count(c, want == .done ? "typed" : "refused")
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "KeyWatch and globalKey with a fake source; typeText with a fake typist"
    }
}
