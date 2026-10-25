import CairnFrame
import CairnHost
import CairnRender
import Foundation

/// The image cache's budget (`Sub.imageCache`, ^1011):
///
/// `images.cache`, two ways:
///
/// - The store: an `ImageStore` with a budget, driven by random puts, removals, drawn
///   sets and budget changes, against a model of least-recently-used eviction. After each step
///   the store holds exactly what the model does; it dropped only entries neither drawn nor just
///   put, oldest use first, and only while over budget; it is over budget only when nothing more
///   can be dropped; and `onDrop` heard of every entry that went, once, after it was gone.
/// - Ready means held: the real `World` with an `imageCache` subscription, `loadImage`
///   requests on files (some reloaded, some of files since deleted) running concurrently, and
///   frames drawing what the app takes for ready. The events are fed in order to a copy of
///   Lean's `Images` table (`receive`, `evicted`); once every request is answered and every
///   notice sent, every image the table takes for ready is in the store.
final class CacheSuite: Suite {
    let name = "cache"
    let crashCheck = "images.cache"
    let checks: [String: CheckInfo] = [
        "images.cache": CheckInfo(
            title: "The image cache reports every image it drops, after it is gone",
            trusted: ["host/Sources/CairnRender/Images.swift (ImageStore: setBudget, setDrawn, put, remove)",
                      "host/Sources/CairnHost/World.swift (imageCache, Handlers.devices)",
                      "host/Sources/CairnHost/ImageEffects.swift"],
            oracle: "a least-recently-used model of the store; a copy of Lean's Images table fed the World's events in order, and the store at the end"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 10) }

    var dir: URL!
    /// Encoded pictures by side: 4×4 up to 32×32 pixels.
    var pngs: [Int: Data] = [:]

    func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cairn-cache-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for side in [4, 8, 16, 32] {
            pngs[side] = ImageSuite.encode(ImageSuite.Pic(w: side, h: side, quads: Array(ImageSuite.palette.prefix(4)),
                                                          type: "public.png", orientation: 1))!
        }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        storeCase(&g, r)
        readyCase(&g, r)
    }

    // MARK: The store against a model

    struct Model {
        var size: [String: Int] = [:]
        var used: [String: Int] = [:]
        var drawn: Set<String> = []
        var budget: Int?
        var clock = 0
        var held: Int { size.values.reduce(0, +) }
        /// Drops in the store's order: oldest use first (ties by name), skipping `keeping` and drawn.
        mutating func trim(keeping: String?) -> [String] {
            guard let budget, held > budget else { return [] }
            let order = used.filter { $0.key != keeping && !drawn.contains($0.key) }
                .sorted { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }
            var out: [String] = []
            for (s, _) in order {
                guard held > budget else { break }
                size[s] = nil; used[s] = nil; out.append(s)
            }
            return out
        }
    }

    func storeCase(_ g: inout SplitMix, _ r: Recorder) {
        let check = "images.cache"
        r.ran(check)
        let store = ImageStore()
        let heard = Locked<[String]>([])
        let notGone = Locked<[String]>([])
        var m = Model()
        let names = (0..<g.range(2, 10)).map { "s\($0)" }
        var decoded: [Int: ImageStore.Decoded] = [:]
        for (side, data) in pngs { decoded[side] = ImageStore.decode(data)! }
        func bytes(_ side: Int) -> Int { side * side * 4 }
        func setBudget(_ b: Int?) {
            store.setBudget(b) { s in
                heard.update { $0.append(s) }
                if store.entry(s) != nil { notGone.update { $0.append(s) } }
            }
            m.budget = b.map { max(0, $0) }
        }
        setBudget(g.range(0, 4 * bytes(32)))
        // The entry the store last kept although over budget because it was just put: it trims
        // again only on the next put, frame or budget, so until then it may stay.
        var kept: String?
        for step in 0..<g.range(5, 60) {
            heard.value = []
            var want: [String] = []
            var keeping: String?
            var what = ""
            switch g.below(10) {
            case 0...4:
                let s = g.elem(names), side = g.elem([4, 8, 16, 32])
                store.put(s, decoded[side]!)
                m.size[s] = bytes(side)
                m.clock += 1
                m.used[s] = m.clock
                keeping = s
                kept = s
                want = m.trim(keeping: s)
                what = "put \(s) \(side)×\(side)"
            case 5:
                let s = g.elem(names)
                store.remove(s)
                if m.size.removeValue(forKey: s) != nil { want = [s] }
                m.used[s] = nil
                if kept == s { kept = nil }
                what = "remove \(s)"
            case 6...8:
                let d = Set(names.filter { _ in g.below(3) == 0 })
                store.setDrawn(d)
                m.drawn = d
                kept = nil
                m.clock += 1
                for s in d where m.size[s] != nil { m.used[s] = m.clock }
                want = m.trim(keeping: nil)
                what = "drawn \(d.sorted())"
            default:
                let b: Int? = g.below(4) == 0 ? nil : g.range(0, 4 * bytes(32))
                setBudget(b)
                kept = nil
                want = m.trim(keeping: nil)
                what = "budget \(b.map(String.init) ?? "none")"
            }
            r.count(check, "steps")
            let got = heard.value
            if got != want {
                r.fail(check, "step \(step) (\(what)): dropped \(got), the model drops \(want)")
                return
            }
            if !notGone.value.isEmpty { r.fail(check, "onDrop heard of \(notGone.value) while still held"); return }
            // A removal (a failed reload) may take a drawn entry; a trim never does.
            for s in got where !what.hasPrefix("remove") {
                if m.drawn.contains(s) { r.fail(check, "step \(step): dropped \(s), which is drawn"); return }
                if s == keeping { r.fail(check, "step \(step): dropped \(s), just put"); return }
            }
            for s in names where (store.entry(s) != nil) != (m.size[s] != nil) {
                r.fail(check, "step \(step) (\(what)): \(s) is \(store.entry(s) != nil ? "" : "not ")held; the model says otherwise")
                return
            }
            if store.bytes != m.held { r.fail(check, "step \(step): \(store.bytes) bytes held, the model \(m.held)"); return }
            if let b = m.budget, m.held > b {
                let droppable = m.size.keys.filter { $0 != kept && !m.drawn.contains($0) }
                if !droppable.isEmpty { r.fail(check, "step \(step): over budget with \(droppable) droppable"); return }
                r.count(check, "over budget, nothing droppable")
            }
            if !got.isEmpty { r.count(check, "drops", got.count) }
        }
    }

    // MARK: Ready means held, through the World

    /// Lean's `Images` table: `load`, `receive`, `evicted`.
    struct Table {
        enum State: Equatable { case loading, ready, failed }
        var known: [String: State] = [:]
        var pending: [(UInt32, String)] = []
        mutating func load(_ id: UInt32, _ s: String) {
            known[s] = .loading
            pending = [(id, s)] + pending.filter { $0.1 != s }
        }
        mutating func receive(_ id: UInt32, _ rep: Reply) {
            guard let s = pending.first(where: { $0.0 == id })?.1 else { return }
            if case .image = rep { known[s] = .ready } else { known[s] = .failed }
            pending.removeAll { $0.0 == id }
        }
        mutating func evicted(_ s: String) {
            if known[s] == .ready { known[s] = .loading }
            pending.removeAll { $0.1 == s }
        }
        var ready: Set<String> { Set(known.filter { $0.value == .ready }.keys) }
    }

    func readyCase(_ g: inout SplitMix, _ r: Recorder) {
        let check = "images.cache"
        r.ran(check)
        let caseDir = dir.appendingPathComponent("\(g.next())")
        try? FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: caseDir) }
        let n = g.range(3, 10)
        let paths = (0..<n).map { caseDir.appendingPathComponent("p\($0).png").path }
        var sides: [Int] = []
        for p in paths {
            let side = g.elem([8, 16, 32])
            sides.append(side)
            FileManager.default.createFile(atPath: p, contents: pngs[side])
        }
        let store = ImageStore()
        let world = World(handlers: Handlers(table: [:]), devices: .inert, images: store)
        let mail = Mailbox()
        world.send = { es in mail.add(es) { _ in nil } }
        let budget = UInt64(g.range(0, 3 * 32 * 32 * 4))
        world.run([], [.start(id: 1, .imageCache(bytes: budget))])

        var table = Table()
        var heard = 0
        var asked: [UInt32] = []
        var nextId: UInt32 = 10
        func hear() {
            let es = mail.all
            while heard < es.count {
                switch es[heard] {
                case let .reply(id, rep): table.receive(id, rep)
                case let .subEvent(1, .evicted(s)): table.evicted(s); r.count(check, "evicted")
                default: break
                }
                heard += 1
            }
        }
        for _ in 0..<g.range(4, 30) {
            switch g.below(8) {
            case 0...3:
                var effects: [Effect] = []
                for _ in 0..<g.range(1, 4) {
                    let p = g.elem(paths)
                    let reload = g.bool()
                    table.load(nextId, p)
                    asked.append(nextId)
                    effects.append(.request(id: nextId, .loadImage(source: p, reload: reload)))
                    nextId += 1
                }
                world.run(effects, [])
            case 4, 5:
                hear()
                // The app draws what it takes for ready (all of it, or some, as a page would).
                let shown = table.ready.filter { _ in g.below(3) != 0 }
                let draws = shown.sorted().map { Draw.image(Rect(x: 0, y: 0, w: 1, h: 1), dest: Rect(x: 0, y: 0, w: 1, h: 1), source: $0) }
                world.drawing(Frame(size: Size(w: 10, h: 10), draws: draws))
                r.count(check, "frames")
            case 6:
                // A file goes away (a later reload of it fails and is removed) or comes back.
                let i = g.below(n)
                if FileManager.default.fileExists(atPath: paths[i]) {
                    try? FileManager.default.removeItem(atPath: paths[i])
                } else {
                    FileManager.default.createFile(atPath: paths[i], contents: pngs[sides[i]])
                }
            default:
                usleep(UInt32(g.range(0, 3000)))
            }
        }
        // Every request answered, then every notice sent (the queue drained).
        let end = Date().addingTimeInterval(10)
        func answered() -> Set<UInt32> {
            Set(mail.all.compactMap { if case let .reply(id, _) = $0 { id } else { nil } })
        }
        while !Set(asked).isSubset(of: answered()) {
            if Date() > end { r.fail(check, "requests not answered: \(Set(asked).subtracting(answered()))"); break }
            usleep(500)
        }
        _ = world.running
        hear()
        for s in table.ready.sorted() where store.entry(s) == nil {
            r.fail(check, "the app takes \((s as NSString).lastPathComponent) for ready, but the store has no pixels for it (budget \(budget), held \(store.bytes))")
        }
        r.count(check, "ready at the end", table.ready.count)
        if store.bytes > Int(budget) { r.count(check, "over budget at the end (drawn or just put)") }
        world.reset()
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "store steps and a World run with an imageCache budget (seeded)"
    }
}
