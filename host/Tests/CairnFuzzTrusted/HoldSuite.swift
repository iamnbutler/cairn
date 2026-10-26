import CairnFrame
import CairnHost
import Foundation

/// An app for the held world: like `WakeCore` it records every batch and can ask for a wake,
/// and its next frame can carry requests (`emit`), so they reach the engine's `World`.
final class HoldCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[Event]] = []
    private var wake: UInt64?
    private var pending: [Effect] = []

    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) { lock.withLock { batches.append(events) } }
    func frame() throws -> Frame {
        lock.withLock {
            let e = pending
            pending = []
            return Frame(size: Size(w: 10, h: 10), draws: [], effects: e, wake: wake)
        }
    }
    /// The next frame asks to be woken at `w` (monotonic ms), and every frame after it until
    /// `wake(nil)`.
    func wake(_ w: UInt64?) { lock.withLock { wake = w } }
    func emit(_ e: [Effect]) { lock.withLock { pending += e } }
    var log: [[Event]] { lock.withLock { batches } }
}

/// The debug socket's `holdWorld` (`Engine.holdClock`, `World.holdRequests`), against what
/// conformance assumes of it (docs/conformance.md, "The world"):
///
/// - `world.hold`: once both have returned, no batch Lean hears holds anything the host made up
///   (no clock of its own, no wake, no reply to a request): each one is exactly the events the
///   caller sent, in order, the driver's `clock` and `reply` events among them; no request
///   handed over afterwards is run or answered; and Lean never hears an empty batch, before or
///   after. Requests from before the hold may still be answered once each.
final class HoldSuite: Suite {
    let name = "hold"
    let crashCheck = "world.hold"
    let checks: [String: CheckInfo] = [
        "world.hold": CheckInfo(
            title: "Under holdWorld the host sends no clock, wake or reply of its own",
            trusted: ["host/Sources/CairnHost/Engine.swift (holdClock)", "host/Sources/CairnHost/World.swift (holdRequests)"],
            oracle: "the events the case sent after the hold, and the requests' handlers"),
    ]

    func cases(for n: Int) -> Int { max(2, n / 40) }
    func setUp() {}

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let check = "world.hold"
        let ran = Locked<[UInt32]>([])
        // Every request kind answers at once, recording that it ran (by the id in its path).
        var table: [UInt8: RequestHandler] = [:]
        for k in WorldSuite.kinds {
            table[k.kindCode] = { req, reply in
                if case let .readFile(path) = req, let id = UInt32(path) { ran.update { $0.append(id) } }
                reply(.done)
            }
        }
        let world = World(handlers: Handlers(table: table), devices: .inert)
        let core = HoldCore()
        let engine = Engine(size: Size(w: 10, h: 10), scalePercent: 100, world: world) { core }
        engine.start()
        defer { engine.stop() }
        guard engine.wait(through: 0) != nil else { r.fail(check, "no first frame"); return }

        var nextId: UInt32 = 1
        func request() -> Effect {
            let id = nextId
            nextId += 1
            return .request(id: id, .readFile(path: String(id)))
        }

        // Before the hold: requests, and a wake that is about due as the hold comes, so a wake
        // timer races it.
        var before: Set<UInt32> = []
        for _ in 0..<g.range(0, 3) {
            let e = request()
            if case let .request(id, _) = e { before.insert(id) }
            core.emit([e])
        }
        let d = UInt64(g.elem([0, 0, 1, 1, 2, 3, 5]))
        core.wake(HostClock.monoMs() + d)
        _ = engine.wait(through: engine.send([.pointerExit]))
        usleep(UInt32(g.elem([0, 0, 200, 500, 900, 1500, 2500, 4000])))
        engine.holdClock()
        world.holdRequests()

        // A marker: every batch after the one that holds it was taken after the hold.
        let marker = Event.resize(Size(w: 4321, h: Int32(g.below(1000))))
        _ = engine.wait(through: engine.send([marker]))
        let log0 = core.log
        guard let mi = log0.lastIndex(where: { $0.contains(marker) }) else {
            r.fail(check, "the marker batch never arrived")
            return
        }

        // Held: the case is the driver. It sends clocks, replies and input; the app asks for
        // wakes (some already due) and sends requests, which must never run.
        var sent: [Event] = []
        var heldIds: Set<UInt32> = []
        var mono = UInt64(g.below(1 << 40))
        for _ in 0..<g.range(1, 6) {
            if g.chance(1, 2) {
                let now = HostClock.monoMs()
                core.wake(g.bool() ? now : now + UInt64(g.elem([1, 3, 8])))
                r.count(check, "wakes")
            }
            if g.chance(1, 2) {
                let e = request()
                if case let .request(id, _) = e { heldIds.insert(id) }
                core.emit([e])
            }
            var batch: [Event] = []
            for _ in 0..<g.range(1, 4) {
                switch g.below(4) {
                case 0:
                    mono += UInt64(g.below(5000))
                    batch.append(.clock(Time(mono: mono, wall: Int64(g.below(1 << 50)), zone: Int32(g.below(50_000)) - 25_000)))
                    r.count(check, "clocks")
                case 1:
                    let id = heldIds.isEmpty || g.chance(1, 4) ? 100_000 + UInt32(g.below(1000)) : g.elem(heldIds.sorted())
                    batch.append(.reply(id: id, EventsSuite.reply(&g)))
                    r.count(check, "replies")
                case 2: batch.append(.pointerExit)
                default: batch.append(.resize(Size(w: Int32(g.below(2000)), h: Int32(g.below(2000)))))
                }
            }
            sent += batch
            _ = engine.wait(through: engine.send(batch))
            usleep(UInt32(g.elem([0, 1000, 5000, 12_000])))
        }
        // Long enough for any wake that was asked for and any held request to have run.
        usleep(20_000)
        r.count(check, "requestsHeld", heldIds.count)

        let log = core.log
        for (i, b) in log.enumerated() where b.isEmpty {
            r.fail(check, "batch \(i) of \(log.count) is empty (\(i > mi ? "after" : "before") the hold)")
        }
        // After the marker: exactly what was sent, in order, but for answers to requests from
        // before the hold.
        let heard = log.dropFirst(mi + 1).flatMap { $0 }.filter {
            if case let .reply(id, _) = $0, before.contains(id), !sent.contains($0) { return false }
            return true
        }
        r.expect(check, heard == sent, "after the hold Lean heard \(heard.count) events, the driver sent \(sent.count): \(heard.prefix(6)) vs \(sent.prefix(6))")
        let ranHeld = Set(ran.value).intersection(heldIds)
        r.expect(check, ranHeld.isEmpty, "requests \(ranHeld.sorted()) ran after the hold")
        let open = world.unanswered.intersection(heldIds)
        r.expect(check, open.isEmpty, "requests \(open.sorted()) after the hold are waiting on the host")
        var answers: [UInt32: Int] = [:]
        for e in log.flatMap({ $0 }) { if case let .reply(id, _) = e, before.contains(id) { answers[id, default: 0] += 1 } }
        for (id, c) in answers { r.expect(check, c <= 1, "request \(id) from before the hold answered \(c) times") }
        r.ran(check)
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "Engine.holdClock and World.holdRequests with a HoldCore"
    }
}
