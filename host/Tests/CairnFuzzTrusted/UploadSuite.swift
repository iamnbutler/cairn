import CairnFrame
import CairnHost
import Foundation

/// `upload` and its secret, against a stub server (`StubProtocol`), fake secrets and clips in
/// memory: nothing reaches the network or reads a real secret.
///
/// - `effects.upload`: the server receives one request whose body is the parts in order, each
///   `wav` part the clip's WAV for its windows, with the headers given and the secret header;
///   a missing clip, a bad range or a missing secret is answered `failed` and nothing is sent;
///   otherwise the reply is the server's response. A multipart body built the way Yap's
///   OpenAITranscription builds it, as bytes around a `wav` part, arrives byte for byte.
/// - `effects.secret`: `parseDotEnv` against generated files with a known meaning (comments,
///   blank lines, `export`, quotes, spaces, `=` in values, repeated keys); the environment wins
///   when set and not empty; a missing secret is `notFound`; a secret with a line break is
///   `invalid`; and no secret value appears in any reply, failure message or debug description.
final class UploadSuite: Suite {
    let name = "upload"
    let crashCheck = "effects.upload"
    let checks: [String: CheckInfo] = [
        "effects.upload": CheckInfo(
            title: "`upload` sends the body assembled from its parts, with the secret in its header",
            trusted: ["host/Sources/CairnHost/UploadEffects.swift (Upload)", "World.swift (HTTP)"],
            oracle: "a URLProtocol stub: what it was sent; the parts and clips"),
        "effects.secret": CheckInfo(
            title: "A secret is read from the environment or its file, and never shown",
            trusted: ["host/Sources/CairnHost/UploadEffects.swift (SecretSource)"],
            oracle: "generated KEY=value files whose meaning is known; every reply and message"),
    ]

    var session: URLSession!

    func cases(for n: Int) -> Int { max(4, n / 4) }
    func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: c)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        dotenv(&g, r)
        upload(&g, r)
    }

    // MARK: secrets

    static let keys = ["OPENAI_API_KEY", "A", "KEY_2", "OTHER"]

    /// A value with no surrounding whitespace, no newline and no quotes at both ends.
    static func value(_ g: inout SplitMix) -> String {
        let alphabet = Array("abcXYZ019-_.:/+=# é🙂\"'")
        var s = String((0..<g.range(1, 30)).map { _ in g.elem(alphabet) }).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = "v" }
        if s.count >= 2, (s.first == "\"" && s.last == "\"") || (s.first == "'" && s.last == "'") { s += "x" }
        return s
    }

    /// A file and what it means.
    static func file(_ g: inout SplitMix) -> (String, [String: String]) {
        var lines: [String] = [], meaning: [String: String] = [:]
        for _ in 0..<g.range(0, 12) {
            let sp = { (g: inout SplitMix) in String(repeating: " ", count: g.below(3)) }
            switch g.below(6) {
            case 0: lines.append(sp(&g) + "# " + value(&g))
            case 1: lines.append(g.bool() ? "" : sp(&g))
            case 2: lines.append("no equals " + String(g.below(100)))
            default:
                let k = g.elem(keys), v = value(&g)
                let quoted = g.elem([v, "\"\(v)\"", "'\(v)'"])
                let export = g.chance(1, 4) ? "export " : ""
                lines.append(sp(&g) + export + k + sp(&g) + "=" + sp(&g) + quoted + sp(&g))
                meaning[k] = v
            }
        }
        return (lines.joined(separator: "\n") + (g.bool() ? "\n" : ""), meaning)
    }

    func dotenv(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.secret"
        let (text, meaning) = Self.file(&g)
        let got = SecretSource.parseDotEnv(text)
        r.expect(c, got.filter { Self.keys.contains($0.key) } == meaning, "parseDotEnv(\(text.debugDescription)) = \(got), want \(meaning)")

        let name = g.elem(Self.keys)
        let env: String? = g.elem([nil, "", "env-" + Self.value(&g)])
        let readable = g.chance(4, 5)
        let src = SecretSource(environment: { $0 == name ? env : nil }, readFile: { $0 == "~/s.env" && readable ? text : nil })
        let s = Secret(header: "Authorization", scheme: "Bearer ", file: "~/s.env", name: name)
        let want: String? = (env?.isEmpty == false) ? env : (readable ? meaning[name].flatMap { $0.isEmpty ? nil : $0 } : nil)
        switch src.resolve(s) {
        case let .success(v): r.expect(c, v == want, "resolved \(name) to a value other than \(String(describing: want))")
        case let .failure(e):
            r.expect(c, want == nil && e.fault == .notFound, "\(name) not found, want a value")
            for v in meaning.values where v.count >= 3 {
                r.expect(c, !e.message.contains(v), "the not-found message shows a value from the file")
            }
        }
        r.count(c, want == nil ? "missing" : (env?.isEmpty == false ? "fromEnv" : "fromFile"))
    }

    // MARK: upload

    func call(_ world: World, _ req: Request) -> [Reply] {
        let got = Locked<[Reply]>([])
        let first = DispatchSemaphore(value: 0)
        world.send = { es in
            for case let .reply(_, rep) in es { got.update { $0.append(rep) } }
            first.signal()
        }
        world.run([.request(id: 1, req)], [])
        _ = first.wait(timeout: .now() + 5)
        usleep(2000)
        return got.value
    }

    func upload(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.upload", cs = "effects.secret"
        let key = "u-\(g.next())"
        let secretValue = "sk-" + String((0..<g.range(8, 40)).map { _ in g.elem(Array("abcdefXYZ0123456789")) })
        let badSecret = g.chance(1, 10)
        let hasSecret = g.chance(3, 4), secretMissing = g.chance(1, 8)
        var d = Devices.inert
        d.session = session
        let stored = badSecret ? secretValue + "\r\nX-Evil: 1" : secretValue
        d.secrets = SecretSource(environment: { $0 == "OPENAI_API_KEY" && !secretMissing ? stored : nil }, readFile: { _ in nil })
        let world = World(handlers: Handlers(table: [:]), devices: d)

        // A clip, and a body of bytes and wav parts (sometimes one that can't be cut).
        let clip = UInt32(g.below(3))
        let samples = AudioSuite.signal(&g, g.range(0, 8000))
        world.clips.begin(clip)
        samples.withUnsafeBufferPointer { _ = world.clips.append(clip, $0) }
        world.clips.finish(clip)
        let windows = samples.count / 320
        var parts: [Part] = []
        var want: [UInt8]? = []
        let yapShaped = g.chance(1, 3)
        if yapShaped {
            // Yap's OpenAITranscription body, with Lean writing every byte but the WAV.
            let b = "yap-\(g.next())"
            let head = "--\(b)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"
                + "--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
            parts = [.bytes(Array(head.utf8)), .wav(clip: clip, start: 0, stop: nil), .bytes(Array("\r\n--\(b)--\r\n".utf8))]
            want = Array(head.utf8) + AudioSuite.wavFile(samples[...]) + Array("\r\n--\(b)--\r\n".utf8)
        } else {
            for _ in 0..<g.range(0, 5) {
                if g.bool() {
                    let b = (0..<g.range(0, 40)).map { _ in UInt8(g.below(256)) }
                    parts.append(.bytes(b)); want? += b
                } else {
                    let unknown = g.chance(1, 10)
                    let a = g.range(0, windows + 1), e: Int? = g.chance(1, 3) ? nil : g.range(0, windows + 1)
                    parts.append(.wav(clip: unknown ? clip + 5 : clip, start: UInt32(a), stop: e.map(UInt32.init)))
                    let lo = a * 320, hi = e.map { $0 * 320 } ?? samples.count
                    if unknown || lo > hi || hi > samples.count { want = nil } else { want? += AudioSuite.wavFile(samples[lo..<hi]) }
                }
            }
        }
        let secret = hasSecret ? Secret(header: "Authorization", scheme: "Bearer ", file: "~/nowhere.env", name: "OPENAI_API_KEY") : nil
        let headers = [Header("X-Cairn-Case", key), Header("Content-Type", "multipart/form-data; boundary=x")]
        let status = g.elem([200, 400, 500])
        StubProtocol.answers.update { $0[key] = .respond(status: status, headers: ["X-R": "1"], body: [1, 2]) }
        let req = Request.upload(method: "POST", url: "https://api.example.invalid/v1/audio/transcriptions", headers: headers,
                                 secret: secret, body: parts, timeoutMs: 5000)
        let replies = call(world, req)
        let seen = StubProtocol.seen.value[key]
        StubProtocol.answers.update { $0[key] = nil }
        StubProtocol.seen.update { $0[key] = nil }

        // The secret value shows up nowhere but the header.
        for rep in replies {
            if case let .failed(_, m) = rep { r.expect(cs, !m.contains(secretValue), "a failure message shows the secret") }
        }
        r.expect(cs, !DebugJSON.describe(req).contains(secretValue), "the debug description shows the secret")

        guard replies.count == 1 else { r.fail(c, "\(replies.count) replies: \(replies)"); return }
        let rep = replies[0]
        func failed(_ f: Fault) -> Bool { if case .failed(f, _) = rep { true } else { false } }
        if want == nil {
            r.expect(c, (failed(.invalid) || failed(.notFound)) && seen == nil, "a bad wav part answered \(rep), sent \(seen != nil)")
            r.count(c, "badPart")
        } else if hasSecret && secretMissing {
            r.expect(cs, failed(.notFound) && seen == nil, "a missing secret answered \(rep), sent \(seen != nil)")
            r.count(cs, "missingSecret")
        } else if hasSecret && badSecret {
            r.expect(cs, failed(.invalid) && seen == nil, "a secret with CR LF answered \(rep), sent \(seen != nil)")
            r.count(cs, "badSecret")
        } else {
            guard let seen else { r.fail(c, "nothing sent; replied \(rep)"); return }
            r.expect(c, seen.body == want!, "the body sent (\(seen.body.count) bytes) is not the parts (\(want!.count))")
            r.expect(c, seen.method == "POST" && seen.headers["Content-Type"] == "multipart/form-data; boundary=x", "method or headers changed: \(seen.method) \(seen.headers.keys.sorted())")
            r.expect(cs, seen.headers["Authorization"] == (hasSecret ? "Bearer " + secretValue : nil), "the Authorization header is wrong")
            r.expect(c, rep == .http(status: UInt32(status), headers: [Header("X-R", "1")], body: [1, 2]) || {
                if case let .http(st, hs, b) = rep { st == UInt32(status) && b == [1, 2] && hs.contains(Header("X-R", "1")) } else { false }
            }(), "replied \(rep)")
            r.count(c, yapShaped ? "multipart" : "sent")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "parseDotEnv and upload against a stub server and fake secrets"
    }
}
