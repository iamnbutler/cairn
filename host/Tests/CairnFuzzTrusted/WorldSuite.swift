import CairnFrame
import CairnHost
import Foundation

/// Collects what a `World` sends, from any thread, with what was allowed at that moment.
final class Mailbox: @unchecked Sendable {
    let lock = NSLock()
    var events: [Event] = []
    var bad: [String] = []
    func add(_ es: [Event], _ check: ([Event]) -> String?) {
        lock.lock()
        defer { lock.unlock() }
        events += es
        if let m = check(es) { bad.append(m) }
    }
    var all: [Event] { lock.lock(); defer { lock.unlock() }; return events }
    var problems: [String] { lock.lock(); defer { lock.unlock() }; return bad }
}

/// The host's `World` (requests and subscriptions) against the semantics Lean's runtime proofs
/// assume of it (docs/effects.md):
///
/// - `effects.reply-once`: every request whose handler answers is answered exactly once, under
///   its own id, with the handler's first answer, whatever the handler does after (answers
///   again, from other threads, late); a kind with no handler is answered `failed invalid`;
///   after `reset` returns, no answer to a request from before it is sent.
/// - `subs.every`: ticks come only for subscriptions that are started and not yet stopped
///   (`running` is exactly that set after each frame), at most one per period, at least one
///   per few periods, and none after `stop` or `reset` returns.
final class WorldSuite: Suite {
    let name = "world"
    let crashCheck = "effects.reply-once"
    let checks: [String: CheckInfo] = [
        "effects.reply-once": CheckInfo(
            title: "The host answers every request exactly once, with its id",
            trusted: ["host/Sources/CairnHost/World.swift"],
            oracle: "the requests sent and what each handler answered first; reset's return"),
        "subs.every": CheckInfo(
            title: "`every ms` ticks while started and never after it is stopped",
            trusted: ["host/Sources/CairnHost/World.swift"],
            oracle: "the started/stopped model of the subscription commands; the monotonic clock"),
    ]

    func cases(for n: Int) -> Int { max(2, n / 10) }
    func setUp() {}

    /// What a fuzzed handler does with one request.
    enum Plan { case none, answer([Reply], async: Bool, delayUs: Int) }

    static let kinds: [Request] = [.readFile(path: "a"), .writeFile(path: "b", data: [1]), .playSound(name: "c"),
                                   .http(method: "GET", url: "http://x", headers: [], body: [], timeoutMs: 0),
                                   .appendFile(path: "d", data: [2]), .listDir(path: "e"), .deleteFile(path: "f"),
                                   .frontmostApp, .permission(.microphone, prompt: false)]

    func replyOnce(_ g: inout SplitMix, _ r: Recorder) {
        let check = "effects.reply-once"
        // Each request's plan, keyed by id (ids are distinct, as Lean's `nextReq` makes them).
        let n = g.range(1, 24)
        var ids = Set<UInt32>()
        while ids.count < n { ids.insert(EventsSuite.u32(&g)) }
        let order = Array(ids)
        var plans: [UInt32: Plan] = [:]
        var requests: [Effect] = []
        let missingKind = UInt8(g.below(5))  // 4: every kind has a handler
        for id in order {
            let req = g.elem(Self.kinds)
            plans[id] = g.chance(1, 8) ? Plan.none
                : .answer((0..<g.range(1, 3)).map { _ in EventsSuite.reply(&g) }, async: g.bool(), delayUs: g.elem([0, 0, 50, 500, 3000]))
            requests.append(.request(id: id, req))
            if g.chance(1, 4) { requests.append(g.elem([.beep, .quit, .setTimer(name: "t", ms: 5)])) }
        }
        let resetAfterUs: Int? = g.chance(1, 4) ? g.elem([0, 100, 1000, 2500]) : nil
        r.count(check, "requests", n)
        if resetAfterUs != nil { r.count(check, "resets") }

        let byId = plans
        let done = DispatchGroup()
        let world = World(handlers: Handlers(table: [:]), devices: .inert)
        let mail = Mailbox()
        let resetDone = Locked(false)
        world.send = { es in
            mail.add(es) { es in resetDone.value ? "a reply after reset returned: \(es)" : nil }
        }
        // World hands a handler only the request, so each request is run with a table entry
        // made for it (World takes the handler when it starts the request).
        var answered: Set<UInt32> = []
        for e in requests {
            guard case let .request(id, req) = e else { continue }
            let plan = byId[id]!
            let k = req.kindCode
            if k == missingKind {
                answered.insert(id)
                world.run([e], [])
                continue
            }
            done.enter()
            world.handlers.table[k] = { _, reply in
                defer { done.leave() }
                guard case let .answer(rs, async, delay) = plan else { return }
                if async {
                    let inner = DispatchGroup()
                    for x in rs {
                        inner.enter()
                        DispatchQueue.global().async {
                            if delay > 0 { usleep(UInt32(delay)) }
                            reply(x)
                            inner.leave()
                        }
                    }
                    inner.wait()
                } else {
                    if delay > 0 { usleep(UInt32(delay)) }
                    for x in rs { reply(x) }
                }
            }
            world.run([e], [])
        }
        if let us = resetAfterUs {
            usleep(UInt32(us))
            world.reset()
            resetDone.value = true
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            r.fail(check, "handlers did not finish in 5 s")
            return
        }
        usleep(2000)
        let got = mail.all
        for p in mail.problems { r.fail(check, p) }
        var count: [UInt32: Int] = [:]
        var first: [UInt32: Reply] = [:]
        for e in got {
            guard case let .reply(id, rep) = e else {
                r.fail(check, "the world sent a non-reply: \(e)")
                continue
            }
            count[id, default: 0] += 1
            if first[id] == nil { first[id] = rep }
        }
        for id in order {
            let c = count[id] ?? 0
            r.expect(check, c <= 1, "request \(id) answered \(c) times")
            guard byId[id] != nil else { continue }
            if answered.contains(id) {
                // No handler for its kind: answered `failed invalid`, at once (before any reset).
                let ok = c == 1 && { if case .failed(.invalid, _) = first[id]! { true } else { false } }()
                r.expect(check, ok, "request \(id) with no handler: \(c) answers, first \(String(describing: first[id]))")
                continue
            }
            switch byId[id]! {
            case .none:
                r.expect(check, c == 0, "request \(id) whose handler never answers was answered")
            case let .answer(rs, async, _):
                if resetAfterUs == nil {
                    r.expect(check, c == 1, "request \(id) answered \(c) times, expected once")
                }
                // In order, the first answer wins; answers racing on other threads, one of them.
                if c == 1 {
                    let ok = async ? rs.contains(first[id]!) : first[id] == rs[0]
                    r.expect(check, ok, "request \(id) answered \(first[id]!), the handler answered \(rs)")
                }
            }
        }
        for id in count.keys where !ids.contains(id) { r.fail(check, "an answer under id \(id), which no request had") }
        world.reset()
    }

    func every(_ g: inout SplitMix, _ r: Recorder) {
        let check = "subs.every"
        let world = World(devices: .inert)
        let mail = Mailbox()
        // The model: id → (period, started at), and the ids in the frame being run.
        let state = Locked<(active: [UInt32: (ms: UInt32, since: UInt64)], inRun: Set<UInt32>)>(([:], []))
        var ticks: [UInt32: [UInt64]] = [:]
        let tickLog = Locked<[(UInt32, UInt64)]>([])
        world.send = { es in
            let now = HostClock.monoMs()
            mail.add(es) { es in
                for e in es {
                    guard case let .subEvent(id, .tick) = e else { return "the world sent \(e)" }
                    let s = state.value
                    if s.active[id] == nil && !s.inRun.contains(id) { return "a tick of \(id), which is not running" }
                    tickLog.update { $0.append((id, now)) }
                }
                return nil
            }
        }
        let ids: [UInt32] = [0, 1, 2, UInt32.max, EventsSuite.u32(&g)]
        var periods: [UInt32: [(ms: UInt32, from: UInt64, to: UInt64)]] = [:]
        let rounds = g.range(1, 8)
        for _ in 0..<rounds {
            var cmds: [SubCmd] = []
            for _ in 0..<g.range(0, 4) {
                let id = g.elem(ids)
                cmds.append(g.chance(2, 3) ? .start(id: id, .every(ms: g.elem([1, 2, 5, 10, 20, 40]))) : .stop(id: id))
            }
            let touched = Set(cmds.map { c -> UInt32 in
                switch c { case let .start(id, _), let .stop(id): id }
            })
            state.update { $0.inRun = touched }
            // A start replaces a running subscription of the same id (Lean only does so for a
            // changed sub); the model ends the old period here.
            world.run([], cmds)
            let now = HostClock.monoMs()
            state.update { s in
                for c in cmds {
                    switch c {
                    case let .start(id, .every(ms)):
                        if let old = s.active[id] { periods[id, default: []].append((old.ms, old.since, now)) }
                        s.active[id] = (ms, now)
                    case let .stop(id):
                        if let old = s.active.removeValue(forKey: id) { periods[id, default: []].append((old.ms, old.since, now)) }
                    case .start(_, .watchFile), .start(_, .record), .start(_, .globalKey), .start(_, .imageCache): break  // not generated here
                    }
                }
                s.inRun = []
            }
            let want = Set(state.value.active.keys)
            r.expect(check, world.running == want, "running \(world.running.sorted()) after \(cmds), the model has \(want.sorted())")
            r.count(check, "commands", cmds.count)
            usleep(UInt32(g.elem([0, 1000, 5000, 20_000, 60_000])))
        }
        let end = HostClock.monoMs()
        for (id, a) in state.value.active { periods[id, default: []].append((a.ms, a.since, end)) }
        world.reset()
        r.expect(check, world.running.isEmpty, "running \(world.running.sorted()) after reset")
        state.update { $0.active = [:] }
        usleep(50_000)
        for p in mail.problems { r.fail(check, p) }
        for (id, t) in tickLog.value { ticks[id, default: []].append(t) }
        // Rate: within each period of one subscription, no more ticks than fit (one per ms,
        // with a tick of slack at each end for the ms clock), and at least one when it ran
        // for many periods (generous: the machine may be busy).
        for (id, ps) in periods {
            for p in ps {
                let n = (ticks[id] ?? []).filter { $0 > p.from && $0 <= p.to }.count
                let span = p.to - p.from
                r.count(check, "ticks", n)
                r.expect(check, UInt64(n) <= span / UInt64(p.ms) + 2,
                         "\(n) ticks of \(id) every \(p.ms) ms in \(span) ms")
                if span >= 20 * UInt64(p.ms) && span >= 100 {
                    r.expect(check, n >= 1, "no tick of \(id) every \(p.ms) ms in \(span) ms")
                }
            }
        }
        r.ran(check)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        if g.bool() { replyOnce(&g, r) } else { every(&g, r) }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        g.bool() ? "World.run with fuzzed request handlers" : "World.run with every-subscription commands"
    }
}

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
