import CairnFrame
import CairnHost
import CairnRender
import Foundation

/// A URL protocol that holds a request open until it is stopped, or answers it at once, by the
/// URL's last path component (`hold`, `ok`); it records which loads started and which were
/// stopped before they finished.
final class HoldProtocol: URLProtocol, @unchecked Sendable {
    static let started = Locked<Set<String>>([])
    static let stoppedEarly = Locked<Set<String>>([])
    static let body = Locked<Data>(Data())
    private let finished = Locked(false)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.started.update { $0.insert(path) }
        if path.hasSuffix("/ok") {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body.value)
            client?.urlProtocolDidFinishLoading(self)
            finished.value = true
        }
        // `hold`: never answers; only a cancel ends it.
    }
    override func stopLoading() {
        if !finished.value { Self.stoppedEarly.update { $0.insert(request.url?.path ?? "") } }
    }
}

/// `cancelRequest` (^1009) against the host's `World`, with `http` and `loadImage` requests
/// served by a URL protocol that holds some open until they are cancelled:
///
/// - `effects.cancel`: every request is answered exactly once, cancelled or not; a cancelled
///   request whose load was held open has its load stopped (the `URLSession` task cancelled)
///   and is answered `failed` promptly; a cancelled `loadImage` with `reload` leaves the image
///   the store held for its source; a cancel of an id that was already answered, or never
///   requested, changes nothing; a request cancelled in the same frame it was sent is answered
///   once, without its load starting or with it stopped.
final class CancelSuite: Suite {
    let name = "cancel"
    let crashCheck = "effects.cancel"
    let checks: [String: CheckInfo] = [
        "effects.cancel": CheckInfo(
            title: "`cancelRequest` stops a running request's work; it is still answered once",
            trusted: ["host/Sources/CairnHost/World.swift (Cancellation, World.run)",
                      "host/Sources/CairnHost/ImageEffects.swift", "URLSession (task cancel)"],
            oracle: "a URLProtocol stub that records which loads started and which were stopped early; the store before and after"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 10) }

    var session: URLSession!

    func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [HoldProtocol.self]
        session = URLSession(configuration: c)
        let png = ImageSuite.encode(ImageSuite.Pic(w: 8, h: 6, quads: Array(ImageSuite.palette.prefix(4)),
                                                  type: "public.png", orientation: 1))!
        HoldProtocol.body.value = png
    }

    enum When: CustomStringConvertible {
        case never, sameFrame, afterStart, afterAnswer
        var description: String {
            switch self {
            case .never: "never"
            case .sameFrame: "same frame"
            case .afterStart: "after start"
            case .afterAnswer: "after answer"
            }
        }
    }

    struct Plan: CustomStringConvertible {
        var id: UInt32
        var image: Bool
        var hold: Bool
        var reload: Bool
        var cancel: When
        var description: String {
            "\(id): \(image ? "loadImage\(reload ? " reload" : "")" : "http") \(hold ? "hold" : "ok"), cancel \(cancel)"
        }
    }

    static func plans(_ g: inout SplitMix) -> (tag: UInt64, plans: [Plan], strays: [UInt32]) {
        let tag = g.next()
        var ids = Set<UInt32>()
        let n = g.range(1, 12)
        while ids.count < n { ids.insert(UInt32(g.below(1 << 20))) }
        let plans = ids.sorted().map { id -> Plan in
            let hold = g.bool()
            let cancel: When = hold ? g.elem([.sameFrame, .afterStart]) : g.elem([.never, .never, .sameFrame, .afterAnswer])
            return Plan(id: id, image: g.bool(), hold: hold, reload: g.bool(), cancel: cancel)
        }
        var strays: [UInt32] = []
        for _ in 0..<g.range(0, 3) {
            let x = UInt32(g.below(1 << 20))
            if !ids.contains(x) { strays.append(x) }
        }
        return (tag, plans, strays)
    }

    func url(_ tag: UInt64, _ p: Plan) -> String {
        "https://cancel.test/\(tag)/\(p.id)/\(p.hold ? "hold" : "ok")"
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let check = "effects.cancel"
        let (tag, plans, strays) = Self.plans(&g)
        r.ran(check)
        let store = ImageStore.shared
        let world = World(handlers: Handlers(table: [:]), devices: Devices(
            microphone: Devices.inert.microphone, keys: Devices.inert.keys, typist: Devices.inert.typist,
            secrets: Devices.inert.secrets, session: session))
        let s = session!
        world.handlers.table[3] = { req, reply in
            if case let .http(m, u, hs, b, t, _, _, _) = req {
                HTTP.run(method: m, url: u, headers: hs, body: b, timeoutMs: t, session: s, reply)
            }
        }
        let mail = Mailbox()
        world.send = { es in mail.add(es) { _ in nil } }

        // A kept image for each reload, which a cancelled reload must leave in the store.
        let kept = ImageStore.decode(HoldProtocol.body.value)!
        for p in plans where p.image && p.reload { _ = store.put(url(tag, p), kept) }

        func request(_ p: Plan) -> Effect {
            .request(id: p.id, p.image ? .loadImage(source: url(tag, p), reload: p.reload)
                : .http(method: "GET", url: url(tag, p), headers: [], body: [], timeoutMs: 20000))
        }
        func replies(_ id: UInt32) -> [Reply] {
            mail.all.compactMap { if case let .reply(i, rep) = $0, i == id { rep } else { nil } }
        }
        func wait(_ cond: () -> Bool, _ seconds: Double = 5) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if cond() { return true }
                usleep(500)
            }
            return cond()
        }

        // One frame: every request, with the same-frame cancels after their requests, and stray cancels.
        var frame: [Effect] = []
        for p in plans {
            frame.append(request(p))
            if p.cancel == .sameFrame { frame.append(.cancelRequest(id: p.id)) }
        }
        for x in strays { frame.append(.cancelRequest(id: x)) }
        world.run(frame, [])
        r.count(check, "requests", plans.count)
        r.count(check, "stray cancels", strays.count)

        for p in plans where p.cancel == .afterStart {
            let path = URL(string: url(tag, p))!.path
            if !wait({ HoldProtocol.started.value.contains(path) }) {
                r.fail(check, "\(p): its load never started")
                continue
            }
            world.run([.cancelRequest(id: p.id)], [])
            r.count(check, "cancelled while running")
        }
        for p in plans where p.cancel == .afterAnswer {
            if !wait({ !replies(p.id).isEmpty }) { r.fail(check, "\(p): not answered"); continue }
            world.run([.cancelRequest(id: p.id)], [])
            r.count(check, "cancelled after answering")
        }
        // Every request answers (held ones only because they were cancelled).
        if !wait({ plans.allSatisfy { !replies($0.id).isEmpty } }) {
            let missing = plans.filter { replies($0.id).isEmpty }
            r.fail(check, "not answered within 5 s: \(missing)")
        }
        usleep(20000)  // time for a second answer, if one were coming
        for p in plans {
            let rs = replies(p.id)
            if rs.count != 1 { r.fail(check, "\(p): answered \(rs.count) times: \(rs)"); continue }
            let path = URL(string: url(tag, p))!.path
            if p.hold {
                guard case .failed = rs[0] else { r.fail(check, "\(p): a cancelled held load answered \(rs[0])"); continue }
                let started = HoldProtocol.started.value.contains(path)
                if started, !HoldProtocol.stoppedEarly.value.contains(path) {
                    r.fail(check, "\(p): answered, but its load was never stopped")
                }
                if p.image, p.reload, store.entry(url(tag, p)) == nil {
                    r.fail(check, "\(p): a cancelled reload removed the kept image")
                }
                r.count(check, started ? "held loads stopped" : "cancelled before starting")
            } else if p.cancel == .never || p.cancel == .afterAnswer {
                switch (p.image, rs[0]) {
                case (true, .image(8, 6)), (false, .http(200, _, _)): break
                default: r.fail(check, "\(p): answered \(rs[0])")
                }
            }
        }
        for x in strays where !replies(x).isEmpty {
            r.fail(check, "a cancel of unknown id \(x) was answered: \(replies(x))")
        }
        for p in plans where p.image { store.remove(url(tag, p)) }
        world.reset()
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (_, plans, strays) = Self.plans(&g)
        return "\(plans.count) requests \(plans), stray cancels \(strays)"
    }
}
