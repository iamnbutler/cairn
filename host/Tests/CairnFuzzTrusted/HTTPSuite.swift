import AppKit
import CairnFrame
import CairnHost
import Foundation

/// A URL protocol that answers every request in its session from a script, and records what it
/// was sent. Keyed by the `X-Cairn-Case` header the suite adds to each request.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Answer { case respond(status: Int, headers: [String: String], body: [UInt8]), fail(Int), hang }
    struct Seen { var method: String; var url: String; var headers: [String: String]; var body: [UInt8] }

    static let answers = Locked<[String: Answer]>([:])
    static let seen = Locked<[String: Seen]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Cairn-Case") ?? ""
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
            $0[key] = Seen(method: request.httpMethod ?? "", url: request.url?.absoluteString ?? "",
                           headers: request.allHTTPHeaderFields ?? [:], body: body)
        }
        switch Self.answers.value[key] ?? .fail(NSURLErrorUnknown) {
        case let .respond(status, headers, b):
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(b))
            client?.urlProtocolDidFinishLoading(self)
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code))
        case .hang:
            break  // the session's timeout ends it
        }
    }

    override func stopLoading() {}
}

/// `http` (HTTP.run) against a stub server in the URL loading system:
///
/// - `effects.http`: the request reaches the server with the method, URL, headers and body as
///   given; the reply carries the server's status, headers (sorted by name) and body exactly;
///   a connection failure is `failed network`, a server that never answers `failed timeout`
///   after about the requested time; a URL that isn't http(s), a bad method, a header name that
///   isn't a token or a value with CR, LF or NUL are `failed invalid` and send nothing. Every
///   request is answered exactly once.
final class HTTPSuite: Suite {
    let name = "http"
    let crashCheck = "effects.http"
    let checks: [String: CheckInfo] = [
        "effects.http": CheckInfo(
            title: "`http` sends the request as given and returns the response as received",
            trusted: ["host/Sources/CairnHost/World.swift (HTTP)"],
            oracle: "a URLProtocol stub: what it was sent, and what it answered"),
    ]

    var session: URLSession!

    func cases(for n: Int) -> Int { max(2, n / 4) }
    func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: c)
    }

    static let tchars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")

    static func token(_ g: inout SplitMix) -> String {
        String((0..<g.range(1, 12)).map { _ in g.elem(tchars) })
    }

    /// A header value: printable text from the pool without CR, LF or NUL, trimmed of the
    /// surrounding whitespace HTTP drops.
    static func value(_ g: inout SplitMix) -> String {
        let s = TextPool.string(&g, maxParts: 8).unicodeScalars.filter { $0.value >= 0x21 && $0.value < 0x7F }
        return String(String.UnicodeScalarView(s))
    }

    /// Calls `HTTP.run` and waits for its answers (all of them, to count them).
    func call(method: String, url: String, headers: [Header], body: [UInt8], timeoutMs: UInt32,
              wait: Double = 5) -> [Reply] {
        let got = Locked<[Reply]>([])
        let first = DispatchSemaphore(value: 0)
        HTTP.run(method: method, url: url, headers: headers, body: body, timeoutMs: timeoutMs, session: session) { rep in
            got.update { $0.append(rep) }
            first.signal()
        }
        _ = first.wait(timeout: .now() + wait)
        usleep(1000)
        return got.value
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let check = "effects.http"
        let key = "\(g.next())"
        let method = g.elem(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "X-CUSTOM"])
        let url = "\(g.bool() ? "https" : "http")://example.test/\(Self.token(&g))?q=\(g.below(1000))"
        var headers = (0..<g.below(5)).map { _ in Header("X-" + Self.token(&g), Self.value(&g)) }
        headers.append(Header("X-Cairn-Case", key))
        let body = (method == "GET" || method == "HEAD") ? [] : EventsSuite.bytes(&g)

        switch g.below(8) {
        case 0:  // refused before sending
            var bad = (method, url, headers)
            switch g.below(5) {
            case 0: bad.1 = g.elem(["file:///etc/hosts", "ftp://x/y", "", "not a url", "javascript:1", "data:,x"])
            case 1: bad.0 = g.elem(["", "GE T", "GET\r\n", "PÖST", "G\u{0}"])
            case 2: bad.2.append(Header(g.elem(["", "a b", "a:b", "x\ny", "é", "(x)"]), "v"))
            default: bad.2.append(Header("X-Bad", g.elem(["a\rb", "a\nb", "a\r\nInjected: 1", "a\u{0}b"])))
            }
            let replies = call(method: bad.0, url: bad.1, headers: bad.2, body: body, timeoutMs: 1000)
            r.expect(check, replies.count == 1, "\(replies.count) answers to a refused request")
            r.expect(check, replies.allSatisfy { if case .failed(.invalid, _) = $0 { true } else { false } },
                     "refused request (\(bad.0) \(bad.1) \(bad.2.map { "\($0.name): \($0.value)" })) answered \(replies)")
            r.expect(check, StubProtocol.seen.value[key] == nil, "a refused request reached the server")
            r.count(check, "refused")
        case 1:  // connection failure
            StubProtocol.answers.update { $0[key] = .fail(g.elem([NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost])) }
            let replies = call(method: method, url: url, headers: headers, body: body, timeoutMs: 1000)
            r.expect(check, replies.count == 1, "\(replies.count) answers to a failed connection")
            r.expect(check, replies.allSatisfy { if case .failed(.network, _) = $0 { true } else { false } },
                     "a failed connection answered \(replies)")
            r.count(check, "network")
        case 2 where g.chance(1, 3):  // never answers
            StubProtocol.answers.update { $0[key] = .hang }
            let ms = UInt32(g.range(50, 200))
            let t0 = Date()
            let replies = call(method: method, url: url, headers: headers, body: body, timeoutMs: ms)
            let took = Date().timeIntervalSince(t0) * 1000
            r.expect(check, replies.count == 1, "\(replies.count) answers to a request that timed out")
            r.expect(check, replies.allSatisfy { if case .failed(.timeout, _) = $0 { true } else { false } },
                     "a server that never answers, \(ms) ms timeout: \(replies)")
            r.expect(check, took >= Double(ms) - 5, "timed out after \(Int(took)) ms of \(ms)")
            r.count(check, "timeouts")
        default:
            let status = g.elem([200, 200, 201, 204, 301, 304, 400, 404, 418, 500, 503, 599, 100 + g.below(500)])
            var rh: [String: String] = [:]
            for _ in 0..<g.below(5) { rh["X-" + Self.token(&g)] = Self.value(&g) }
            let rbody = method == "HEAD" ? [] : EventsSuite.bytes(&g)
            StubProtocol.answers.update { $0[key] = .respond(status: status, headers: rh, body: rbody) }
            let replies = call(method: method, url: url, headers: headers, body: body, timeoutMs: UInt32(g.elem([0, 2000])))
            guard r.expect(check, replies.count == 1, "\(replies.count) answers") else { break }
            let seen = StubProtocol.seen.value[key]
            r.expect(check, seen?.method == method, "the server saw method \(seen?.method ?? "-"), sent \(method)")
            // As Foundation parses it: characters a URL can't hold are percent-encoded.
            let parsed = URL(string: url)?.absoluteString
            r.expect(check, seen?.url == parsed, "the server saw \(seen?.url ?? "-"), sent \(url) (\(parsed ?? "-"))")
            r.expect(check, seen?.body == body, "the server saw \(seen?.body.count ?? -1) body bytes, sent \(body.count)")
            for h in headers {
                let v = seen?.headers.first { $0.key.caseInsensitiveCompare(h.name) == .orderedSame }?.value
                r.expect(check, v == h.value, "the server saw \(h.name): \(v ?? "-"), sent \(h.value)")
            }
            guard case let .http(gotStatus, gotHeaders, gotBody) = replies[0] else {
                r.fail(check, "status \(status) answered \(replies[0])")
                break
            }
            r.expect(check, gotStatus == UInt32(status), "status \(gotStatus), the server sent \(status)")
            r.expect(check, gotBody == rbody, "\(gotBody.count) body bytes, the server sent \(rbody.count)")
            r.expect(check, gotHeaders.map(\.name) == gotHeaders.map(\.name).sorted(), "headers not sorted by name")
            for (k, v) in rh {
                let got = gotHeaders.first { $0.name.caseInsensitiveCompare(k) == .orderedSame }?.value
                r.expect(check, got == v, "response header \(k): \(got ?? "-"), the server sent \(v)")
            }
            r.count(check, "responses")
        }
        StubProtocol.answers.update { $0[key] = nil }
        StubProtocol.seen.update { $0[key] = nil }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "HTTP.run against a URLProtocol stub"
    }
}

/// `playSound` (Sounds): a name the system knows is found (and, with CAIRN_FUZZ_SOUND=1,
/// played: `done`); any other name is `failed notFound`, answered once, without playing.
final class SoundSuite: Suite {
    let name = "sound"
    let crashCheck = "effects.sound"
    let checks: [String: CheckInfo] = [
        "effects.sound": CheckInfo(
            title: "`playSound` starts a known sound and refuses an unknown one",
            trusted: ["host/Sources/CairnHost/World.swift (Sounds)"],
            oracle: "the files in /System/Library/Sounds"),
    ]

    let system: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
        .map { ($0 as NSString).deletingPathExtension }.sorted()
    let audible = ProcessInfo.processInfo.environment["CAIRN_FUZZ_SOUND"] != nil

    func cases(for n: Int) -> Int { max(2, n / 4) }
    func setUp() {}

    /// Runs the main run loop until `play` answers (Sounds answers on the main thread).
    func play(_ name: String) -> [Reply] {
        let got = Locked<[Reply]>([])
        Sounds.play(name) { rep in got.update { $0.append(rep) } }
        let deadline = Date(timeIntervalSinceNow: 3)
        while got.value.isEmpty && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002)) }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        return got.value
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let check = "effects.sound"
        guard !system.isEmpty else { r.fail(check, "no system sounds in /System/Library/Sounds"); return }
        let known = g.elem(system)
        let found = MainActor.assumeIsolated { Sounds.lookup(known) != nil }
        r.expect(check, found, "the system sound \(known) is not found")
        if audible {
            let replies = play(known)
            r.expect(check, replies == [.done], "playing \(known): \(replies)")
        }
        let name = g.bool() ? TextPool.string(&g) : known + TextPool.string(&g, maxParts: 3)
        if !system.contains(name) && !system.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            let replies = play(name)
            r.expect(check, replies.count == 1, "\(replies.count) answers for the unknown sound \(name.debugDescription)")
            r.expect(check, replies.allSatisfy { if case .failed(.notFound, _) = $0 { true } else { false } },
                     "the unknown sound \(name.debugDescription): \(replies)")
            r.count(check, "unknown")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "Sounds.lookup and Sounds.play on system and unknown names"
    }
}
