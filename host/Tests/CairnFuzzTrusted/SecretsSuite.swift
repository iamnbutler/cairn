import CairnFrame
import CairnHost
import Foundation
import Security

/// Secrets in the Keychain (^972, ^973; docs/trusted.md, "Secrets in the Keychain"). Every value
/// is generated here; nothing reads, prints or touches a Keychain item it didn't create.
///
/// - `effects.secret.keychain`: random writes, reads, overwrites and deletes over a few accounts,
///   against a dictionary model, on the in-memory store and, locally, on the real login keychain
///   under a throwaway service (`dev.cairn.fuzz-trusted.keychain.<pid>.<random>`; each case
///   deletes the items it made). The live part is skipped when `CI` is set (no login keychain on
///   a CI runner, and nothing may prompt there) or `CAIRN_FUZZ_KEYCHAIN=0`; the counter says so.
///   Through the world: `forgetSecret` answers `done`, also twice; an `http` whose Keychain secret
///   is missing answers `failed notFound` and reaches no server (a `URLProtocol` stub); one whose
///   item is there sends `scheme ++ value`. The live items are not synchronizable and carry the
///   service and account asked for. Concurrency (#237), once per worker, live only: a child
///   process hammers one throwaway service from several threads at once (reads, writes, deletes,
///   `forgetSecret`, `http` building its secret header and capturing into an item) and must finish
///   within a time limit; on a hang the parent kills it, and either way deletes what it made.
/// - `effects.http.capture`: random JSON object replies with planted marker values in the
///   captured fields, decoys (the same names nested, strings that look alike), escapes and
///   whitespace; missing, repeated and non-string fields, bodies that aren't objects, statuses
///   outside 2xx and a store that fails a write. A valid capture stores each value exactly and
///   Lean gets the body with exactly those values written `""`; anything else fails `invalid`
///   (or passes through, outside 2xx) and the store is as it was. No marker appears in any
///   reply, failure message, the events' bytes (the frame Lean reads), their dump or the debug
///   description of the request.
final class SecretsSuite: Suite {
    let name = "secrets"
    let crashCheck = "effects.http.capture"
    let checks: [String: CheckInfo] = [
        "effects.secret.keychain": CheckInfo(
            title: "The Keychain keeps what it was given for this app",
            trusted: ["host/Sources/CairnHost/SecretEffects.swift (KeychainStore, MemoryStore, ForgetSecret)",
                      "UploadEffects.swift (SecretSource.resolve)", "Security.framework (SecItem*)"],
            oracle: "a dictionary model of the items; a URLProtocol stub for what was sent"),
        "effects.http.capture": CheckInfo(
            title: "Captured reply fields go to the Keychain and never to Lean",
            trusted: ["host/Sources/CairnHost/SecretEffects.swift (JSONCapture, SecretHTTP)", "World.swift (HTTP)"],
            oracle: "generated JSON whose captured fields and blanked form are known; planted markers searched in every output"),
    ]

    var session: URLSession!
    /// The live store, or nil when the live check is skipped (and why).
    var live: KeychainStore?
    var skipReason = ""
    /// Whether this process has run the concurrency check (once per worker: it takes seconds).
    var hammered = false

    func cases(for n: Int) -> Int { max(4, n / 10) }

    func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: c)
        let env = ProcessInfo.processInfo.environment
        if env["CI"] != nil {
            skipReason = "CI"
        } else if env["CAIRN_FUZZ_KEYCHAIN"] == "0" {
            skipReason = "CAIRN_FUZZ_KEYCHAIN=0"
        } else {
            var g = SystemRandomNumberGenerator()
            live = KeychainStore(service: "dev.cairn.fuzz-trusted.keychain.\(getpid()).\(String(g.next(), radix: 36))")
        }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        keychain(&g, r)
        capture(&g, r)
    }

    // MARK: values

    /// A value: printable ASCII, edge text, or a marker; never with NUL (header-bound values are
    /// checked separately) but with quotes, backslashes, newlines and non-ASCII.
    static func value(_ g: inout SplitMix) -> String {
        g.weighted([
            (3, { g in "v-" + String(g.next(), radix: 36) }),
            (2, { g in TextPool.string(&g).replacingOccurrences(of: "\u{0}", with: "0") }),
            (1, { g in String(repeating: g.elem(["a", "é", "🙂", "\"", "\\"]), count: g.range(500, 3000)) }),
            (1, { _ in "" }),
        ])
    }

    /// A marker no other text in the case contains.
    static func marker(_ g: inout SplitMix) -> String {
        "KCM" + String(g.next(), radix: 16) + g.elem(["", "\"q", "\\b", "\nnl", "é", "🙂", "/", "\u{1}"])
    }

    /// The part of a marker that is the same in every encoding (no escapes).
    static func core(_ m: String) -> String { String(m.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }) }

    // MARK: effects.secret.keychain

    func keychain(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.secret.keychain"
        let tag = "c\(String(g.next(), radix: 36))"
        let accounts = (0..<3).map { "\(tag)-\($0)" }
        var stores: [(String, any SecretStore)] = [("memory", MemoryStore())]
        if let live, g.chance(1, 2) { stores.append(("keychain", live)) } else if live == nil {
            r.count(c, "liveSkipped:\(skipReason)")
        }
        for (label, store) in stores {
            defer { for a in accounts { _ = store.delete(a) } }
            var model: [String: String] = [:]
            for _ in 0..<g.range(1, label == "keychain" ? 8 : 20) {
                let a = g.elem(accounts)
                switch g.below(4) {
                case 0, 1:
                    let v = Self.value(&g)
                    switch store.write(a, v) {
                    case .success: model[a] = v
                    case let .failure(e): r.fail(c, "\(label): write \(a) failed: \(e.message)")
                    }
                    r.count(c, "\(label).write")
                case 2:
                    let want = model[a]
                    switch store.read(a) {
                    case let .success(v): r.expect(c, v == want, "\(label): read \(a) gave a value other than the last written (\(v?.count ?? -1) vs \(want?.count ?? -1) characters)")
                    case let .failure(e): r.fail(c, "\(label): read \(a) failed: \(e.message)")
                    }
                    r.count(c, "\(label).read")
                default:
                    if g.bool() {
                        r.expect(c, ForgetSecret.run(a, store) == .done, "\(label): forgetSecret \(a) did not answer done")
                    } else {
                        if case let .failure(e) = store.delete(a) { r.fail(c, "\(label): delete \(a) failed: \(e.message)") }
                    }
                    model[a] = nil
                    r.count(c, "\(label).delete")
                }
            }
            // Every account as the model says, at the end.
            for a in accounts {
                let got = try? store.read(a).get()
                r.expect(c, got == model[a], "\(label): \(a) ends as \(String(describing: got).debugDescription.prefix(200)), the model says \(String(describing: model[a]).debugDescription.prefix(200))")
            }
            if label == "keychain", let live, let a = model.keys.sorted().first {
                attributes(live, a, r)
            }
            // Clean up, and check nothing of this case is left.
            for a in accounts { _ = store.delete(a) }
            r.expect(c, accounts.allSatisfy { (try? store.read($0).get()) == .some(nil) }, "\(label): an item is left after its delete")
        }
        r.expect(c, ForgetSecret.run("", MemoryStore()).isInvalid, "forgetSecret of the empty account is not invalid")
        throughWorld(&g, r)
        if live != nil, !hammered {
            hammered = true
            concurrent(r)
        }
    }

    // MARK: concurrent Keychain calls (#237)

    /// Threads, calls per thread, and how long the child may take. Unserialized, 6 × 40 calls
    /// deadlock every time on macOS 27; serialized they take about 3 s.
    static let hammerThreads = 6, hammerCalls = 40, hammerLimit: TimeInterval = 30
    static let hammerAccounts = ["h0", "h1", "h2"]

    /// Runs `--keychain-hammer` in a child process on a throwaway service, kills it (by pid) if it
    /// hasn't finished in `hammerLimit`, then deletes its items from here: a deadlocked process
    /// can't clean up, and only this executable may delete the items it made.
    func concurrent(_ r: Recorder) {
        let c = "effects.secret.keychain"
        var rng = SystemRandomNumberGenerator()
        let service = "dev.cairn.fuzz-trusted.keychain.\(getpid()).\(String(rng.next(), radix: 36))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        p.arguments = ["--keychain-hammer", service]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        let start = Date()
        do { try p.run() } catch { r.fail(c, "cannot start the Keychain hammer: \(error)"); return }
        let hung = exited.wait(timeout: .now() + Self.hammerLimit) == .timedOut
        if hung {
            kill(p.processIdentifier, SIGKILL)
            exited.wait()
        }
        let seconds = Date().timeIntervalSince(start)
        let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        r.expect(c, !hung, "concurrent Keychain calls on one service did not finish in \(Int(Self.hammerLimit)) s (deadlock, #237)")
        if !hung {
            r.expect(c, p.terminationReason == .exit && p.terminationStatus == 0,
                     "the Keychain hammer ended with \(p.terminationReason == .exit ? "exit" : "signal") \(p.terminationStatus): \(text.prefix(400))")
        }
        let store = KeychainStore(service: service)
        let accounts = Self.hammerAccounts
        for a in accounts { _ = store.delete(a) }
        r.expect(c, accounts.allSatisfy { (try? store.read($0).get()) == .some(nil) }, "the Keychain hammer left an item")
        r.count(c, "keychain.concurrent")
        if r.verbose { print("keychain hammer: \(hung ? "killed after" : "finished in") \(String(format: "%.1f", seconds)) s") }
    }

    /// The child's side (`--keychain-hammer SERVICE`): `hammerThreads` threads each make
    /// `hammerCalls` calls on `SERVICE`'s accounts, through the store and through the effects that
    /// reach it: `read`, `write`, `delete`, `forgetSecret`, `http` with a Keychain secret (reading
    /// the item to build its header) and `http` capturing a field into an item, both against the
    /// stub. Deletes its items at the end. Exit 0, or 1 with the first unexpected answer on stderr.
    static func hammer(service: String) -> Never {
        precondition(service.hasPrefix("dev.cairn.fuzz-trusted.keychain."), "the hammer only touches throwaway services")
        let store = KeychainStore(service: service)
        let accounts = hammerAccounts
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: cfg)
        let secrets = SecretSource(environment: { _ in nil }, readFile: { _ in nil }, store: store)
        let problem = Locked<String?>(nil)
        func note(_ s: String) { problem.update { if $0 == nil { $0 = s } } }
        func wait(_ run: (@escaping @Sendable (Reply) -> Void) -> Void) -> Reply? {
            let got = Locked<Reply?>(nil), sem = DispatchSemaphore(value: 0)
            run { rep in got.update { $0 = rep }; sem.signal() }
            return sem.wait(timeout: .now() + hammerLimit) == .timedOut ? nil : got.value
        }
        let group = DispatchGroup()
        for t in 0..<hammerThreads {
            group.enter()
            let key = "hammer-\(t)"
            StubProtocol.answers.update { $0[key] = .respond(status: 200, headers: [:], body: Array("{\"accessJwt\":\"tok-\(t)\"}".utf8)) }
            Thread.detachNewThread {
                defer { group.leave() }
                for i in 0..<hammerCalls {
                    let a = accounts[(t + i) % accounts.count]
                    switch (t * 7 + i) % 6 {
                    case 0:
                        if case let .failure(e) = store.write(a, "v-\(t)-\(i)") { note("write: \(e.message)") }
                    case 1:
                        if case let .failure(e) = store.read(a) { note("read: \(e.message)") }
                    case 2:
                        if case let .failure(e) = store.delete(a) { note("delete: \(e.message)") }
                    case 3:
                        let rep = ForgetSecret.run(a, store)
                        if rep != .done { note("forgetSecret: \(rep)") }
                    case 4:
                        // The header read: `notFound` when another thread just deleted the item.
                        let rep = wait { reply in
                            SecretHTTP.run(method: "GET", url: "https://pds.example.invalid/x", headers: [Header("X-Cairn-Case", key)],
                                           body: [], timeoutMs: 5000,
                                           secret: Secret(header: "Authorization", scheme: "Bearer ", source: .keychain(account: a)),
                                           capture: [], secrets: secrets, session: session, reply)
                        }
                        switch rep {
                        case .http?, .failed(.notFound, _)?: break
                        default: note("http with a secret: \(rep.map { "\($0)" } ?? "no reply")")
                        }
                    default:
                        let rep = wait { reply in
                            SecretHTTP.run(method: "POST", url: "https://pds.example.invalid/x", headers: [Header("X-Cairn-Case", key)],
                                           body: [], timeoutMs: 5000, secret: nil, capture: [Capture("accessJwt", a)],
                                           secrets: secrets, session: session, reply)
                        }
                        if case .http? = rep {} else { note("http capture: \(rep.map { "\($0)" } ?? "no reply")") }
                    }
                }
            }
        }
        group.wait()
        for a in accounts { _ = store.delete(a) }
        if let p = problem.value {
            FileHandle.standardError.write("keychain hammer: \(p)\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }

    /// The live item is what we asked for: our service and account, not synchronizable, a generic
    /// password. Reads attributes only, of an item this case made.
    func attributes(_ store: KeychainStore, _ account: String, _ r: Recorder) {
        let c = "effects.secret.keychain"
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: store.service,
                                  kSecAttrAccount: account, kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne]
        var out: CFTypeRef?
        let st = KeychainStore.serialized { SecItemCopyMatching(q as CFDictionary, &out) }
        guard r.expect(c, st == errSecSuccess, "the item's attributes: status \(st)"),
              let a = out as? [CFString: Any] else { return }
        r.expect(c, a[kSecAttrService] as? String == store.service && a[kSecAttrAccount] as? String == account,
                 "the item has another service or account")
        let sync = (a[kSecAttrSynchronizable] as? Bool) ?? ((a[kSecAttrSynchronizable] as? NSNumber)?.boolValue ?? false)
        r.expect(c, !sync, "the item is synchronizable")
        r.expect(c, (a[kSecAttrAccessGroup] as? String ?? "").isEmpty, "the item is in an access group: \(a[kSecAttrAccessGroup] ?? "")")
        r.count(c, "keychain.attributes")
    }

    /// Requests through the world with Keychain secrets, against the stub.
    func throughWorld(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.secret.keychain"
        let store = MemoryStore()
        let value = "tok-" + String(g.next(), radix: 36)
        let present = g.bool()
        if present { _ = store.write("access", value) }
        let key = "k-\(g.next())"
        StubProtocol.answers.update { $0[key] = .respond(status: 200, headers: [:], body: Array("{}".utf8)) }
        defer { StubProtocol.answers.update { $0[key] = nil }; StubProtocol.seen.update { $0[key] = nil } }
        let req = Request.http(method: "GET", url: "https://pds.example.invalid/xrpc/x", headers: [Header("X-Cairn-Case", key)],
                               body: [], timeoutMs: 5000, secret: Secret(header: "Authorization", scheme: "Bearer ", source: .keychain(account: "access")))
        let out = SecretsSuite.call(session, store, req)
        let seen = StubProtocol.seen.value[key]
        guard r.expect(c, out.replies.count == 1, "\(out.replies.count) replies") else { return }
        if present {
            r.expect(c, seen?.headers["Authorization"] == "Bearer " + value, "the item's value is not in the header sent")
            r.count(c, "headerSent")
        } else {
            r.expect(c, out.replies[0].isFault(.notFound) && seen == nil, "a missing item answered \(out.replies[0]), sent \(seen != nil)")
            r.count(c, "missingNotSent")
        }
        r.expect(c, !out.leaks(value), "the secret's value shows in a reply, the events or their dump")
        r.expect(c, !DebugJSON.describe(req).contains(value), "the debug description shows the secret")
        // forgetSecret through the world: done, and done again.
        for _ in 0..<2 {
            let f = SecretsSuite.call(session, store, .forgetSecret(account: "access"))
            r.expect(c, f.replies == [.done], "forgetSecret answered \(f.replies)")
        }
        r.expect(c, (try? store.read("access").get()) == .some(nil), "forgetSecret left the item")
    }

    // MARK: running a request

    struct Outcome {
        var replies: [Reply]
        var events: [Event]
        /// Whether `s` (a value or its unescaped core) is anywhere Lean or a person could read it.
        func leaks(_ s: String) -> Bool {
            guard !s.isEmpty else { return false }
            let needle = Array(s.utf8)
            let bytes = encodeEvents(events)
            let dump = Dump.events(events)
            func has(_ hay: [UInt8]) -> Bool {
                guard hay.count >= needle.count else { return false }
                return (0...(hay.count - needle.count)).contains { hay[$0..<($0 + needle.count)].elementsEqual(needle) }
            }
            let messages = replies.compactMap { if case let .failed(_, m) = $0 { m } else { nil } }
            let bodies = replies.compactMap { if case let .http(_, _, b) = $0 { b } else { nil } }
            return has(bytes) || dump.contains(s) || dump.contains(Dump.str(s).dropFirst().dropLast())
                || messages.contains { $0.contains(s) } || bodies.contains { has($0) }
        }
    }

    /// Runs `req` in a world whose Keychain is `store`, and collects every event it sends.
    static func call(_ session: URLSession, _ store: any SecretStore, _ req: Request) -> Outcome {
        var d = Devices.inert
        d.session = session
        d.secrets = SecretSource(environment: { _ in nil }, readFile: { _ in nil }, store: store)
        let world = World(handlers: Handlers(table: [:]), devices: d)
        let got = Locked<[Event]>([])
        let first = DispatchSemaphore(value: 0)
        world.send = { es in
            got.update { $0 += es }
            first.signal()
        }
        world.run([.request(id: 1, req)], [])
        _ = first.wait(timeout: .now() + 5)
        usleep(1500)
        let es = got.value
        return Outcome(replies: es.compactMap { if case let .reply(_, rep) = $0 { rep } else { nil } }, events: es)
    }

    // MARK: effects.http.capture

    /// A JSON string literal for `s`; with `escape`, some ASCII letters as `\u00XX`.
    static func literal(_ s: String, _ g: inout SplitMix, escape: Bool) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += g.bool() ? "\\\\" : "\\u005c"
            case "\n": out += "\\n"
            case "/": out += g.bool() ? "\\/" : "/"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) }
                else if escape, u.isASCII, g.chance(1, 4) { out += String(format: "\\u%04X", u.value) }
                else if u.value > 0xFFFF, g.chance(1, 3) {
                    let v = u.value - 0x10000
                    out += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    static let fields = ["accessJwt", "refreshJwt", "did", "handle", "tök", "a\"b"]
    static let accountPool = ["access", "refresh", "other"]

    static func ws(_ g: inout SplitMix) -> String { g.chance(1, 3) ? g.elem([" ", "\n", "\t", "\r\n  ", "   "]) : "" }

    /// A non-string JSON value, or a nested one that may hold decoys (captured names, marker-like
    /// strings that are not captured).
    static func other(_ g: inout SplitMix, _ decoy: String, depth: Int = 0) -> String {
        g.weighted([
            (2, { g in g.elem(["0", "-1.5e3", "true", "false", "null", "12345678901234567890"]) }),
            (2, { g in literal(TextPool.string(&g).replacingOccurrences(of: "\u{0}", with: ""), &g, escape: true) }),
            (1, { g in
                depth > 2 ? "{}" : "{" + (0..<g.below(3)).map { _ in
                    literal(g.elem(fields), &g, escape: false) + ":" + other(&g, decoy, depth: depth + 1) }.joined(separator: ",") + "}"
            }),
            (1, { g in depth > 2 ? "[]" : "[" + (0..<g.below(3)).map { _ in other(&g, decoy, depth: depth + 1) }.joined(separator: ",") + "]" }),
            (1, { g in literal(decoy, &g, escape: false) }),
        ])
    }

    enum Variant: String, CaseIterable { case valid, missing, nonString, repeated, notObject, non2xx, writeFails, noCapture }

    func capture(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.http.capture"
        let variant = g.weighted([(8, { _ in Variant.valid }), (1, { _ in .missing }), (1, { _ in .nonString }),
                                  (1, { _ in .repeated }), (1, { _ in .notObject }), (1, { _ in .non2xx }),
                                  (1, { _ in .writeFails }), (1, { _ in .noCapture })])
        // The captures: (field, account); fields and accounts may repeat.
        var captures: [Capture] = []
        if variant != .noCapture {
            for _ in 0..<g.range(1, 3) { captures.append(Capture(g.elem(Self.fields), g.elem(Self.accountPool))) }
        }
        let capturedFields = Array(Set(captures.map(\.field))).sorted()
        var markers: [String: String] = [:]
        for f in capturedFields { markers[f] = Self.marker(&g) }
        let decoy = "decoy-" + String(g.next(), radix: 36)

        // Members: the captured fields (as the variant says) among others, in random order.
        var members: [(key: String, value: String, blanked: String)] = []
        for f in capturedFields {
            let lit = Self.literal(markers[f]!, &g, escape: true)
            members.append((Self.literal(f, &g, escape: true), lit, "\"\""))
        }
        let spoiled = capturedFields.isEmpty ? nil : g.elem(capturedFields)
        if let s = spoiled, let i = members.firstIndex(where: { (try? JSONSerialization.jsonObject(with: Data($0.key.utf8), options: .fragmentsAllowed)) as? String == s }) {
            switch variant {
            case .missing: members.remove(at: i)
            case .nonString:
                let v = g.elem(["0", "null", "true", "{\"x\":\"\(markers[s]!.prefix(3))\"}", "[\"a\"]"])
                members[i] = (members[i].key, v, v)
            case .repeated: members.append((Self.literal(s, &g, escape: true), Self.literal("dup", &g, escape: false), "\"dup\""))
            default: break
            }
        }
        var used = Set<String>()
        for _ in 0..<g.below(5) {
            var k = "k" + String(g.below(50))
            if g.chance(1, 4) { k = g.elem(["x", "y", "日本", "a b", ""]) }
            if Self.fields.contains(k) || !used.insert(k).inserted { continue }
            let v = Self.other(&g, decoy)
            members.append((Self.literal(k, &g, escape: g.bool()), v, v))
        }
        // Shuffle.
        for i in stride(from: members.count - 1, to: 0, by: -1) { members.swapAt(i, g.below(i + 1)) }
        // Same whitespace in both forms.
        var body = Self.ws(&g) + "{", blanked = body
        for (i, m) in members.enumerated() {
            let w = (Self.ws(&g), Self.ws(&g), Self.ws(&g), Self.ws(&g))
            let sep = i == 0 ? "" : ","
            body += sep + w.0 + m.key + w.1 + ":" + w.2 + m.value + w.3
            blanked += sep + w.0 + m.key + w.1 + ":" + w.2 + m.blanked + w.3
        }
        let tail = "}" + Self.ws(&g)
        body += tail; blanked += tail
        if variant == .notObject {
            body = g.elem(["[" + (members.first?.value ?? "1") + "]", String(body.dropLast(max(1, body.count / 3))),
                           "", "null", "\"\(markers.values.first ?? "x")\"", "<html>", body + "x", "{\"a\":1,}"])
        }
        let status = variant == .non2xx ? g.elem([301, 400, 401, 404, 500, 503]) : g.elem([200, 200, 201, 202, 299])

        // The store: some items already there, some failing writes.
        let mem = MemoryStore()
        for a in Self.accountPool where g.bool() { _ = mem.write(a, "old-" + String(g.next(), radix: 36)) }
        _ = mem.write("unrelated", "keep-" + String(g.next(), radix: 36))
        let before = mem.snapshot
        let failing = variant == .writeFails ? captures.last?.account : nil
        let store = FailingStore(mem, failing: failing)

        let key = "cap-\(g.next())"
        StubProtocol.answers.update { $0[key] = .respond(status: status, headers: ["Content-Type": "application/json"], body: Array(body.utf8)) }
        defer { StubProtocol.answers.update { $0[key] = nil }; StubProtocol.seen.update { $0[key] = nil } }
        let req = Request.http(method: "POST", url: "https://pds.example.invalid/xrpc/com.example.session",
                               headers: [Header("X-Cairn-Case", key)], body: Array("{}".utf8), timeoutMs: 5000, capture: captures)
        let out = Self.call(session, store, req)
        r.count(c, variant.rawValue)
        guard r.expect(c, out.replies.count == 1, "\(out.replies.count) replies") else { return }
        let rep = out.replies[0]

        // What should have happened. A valid capture whose body JSONSerialization doesn't take
        // as an object can't be generated (the generator writes valid JSON for every other variant).
        switch variant {
        case .noCapture, .non2xx:
            let passed: Bool = { if case let .http(st, _, b) = rep { st == UInt32(status) && b == Array(body.utf8) } else { false } }()
            r.expect(c, passed, "\(variant): the reply is not the server's, unchanged: \(rep)")
            r.expect(c, mem.snapshot == before, "\(variant): the store changed")
            return  // the markers are in the body on purpose: nothing was captured
        case .valid:
            let ok: Bool = { if case let .http(st, _, b) = rep { st == UInt32(status) && b == Array(blanked.utf8) } else { false } }()
            r.expect(c, ok, "valid: the reply is not the body with the captured values blanked: \(Self.show(rep)) want \(blanked.debugDescription)")
            var want = before
            for cp in captures { want[cp.account] = markers[cp.field] }
            r.expect(c, mem.snapshot == want, "valid: the store holds something other than the captured values")
        case .missing, .nonString, .repeated, .notObject, .writeFails:
            let f: Fault = variant == .writeFails ? .other : .invalid
            r.expect(c, rep.isFault(f), "\(variant): answered \(Self.show(rep)), want failed \(f)")
            r.expect(c, mem.snapshot == before, "\(variant): the store changed (all or nothing)")
        }
        for (f, m) in markers {
            r.expect(c, !out.leaks(m) && !out.leaks(Self.core(m)), "the captured value of \(f) shows in a reply, the events or their dump")
            r.expect(c, !DebugJSON.describe(req).contains(Self.core(m)), "the debug description shows a captured value")
        }
    }

    static func show(_ rep: Reply) -> String {
        if case let .http(st, _, b) = rep { return "http \(st) \(String(decoding: b, as: UTF8.self).debugDescription)" }
        return "\(rep)"
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "Keychain store model check\(live == nil ? " (live skipped: \(skipReason))" : " and the live keychain") and http capture against a stub"
    }
}

/// A store that fails every write to one account (a full or locked keychain).
final class FailingStore: SecretStore, @unchecked Sendable {
    let base: MemoryStore
    let failing: String?
    init(_ base: MemoryStore, failing: String?) { self.base = base; self.failing = failing }
    func read(_ a: String) -> Result<String?, ReplyError> { base.read(a) }
    func write(_ a: String, _ v: String) -> Result<Void, ReplyError> {
        a == failing ? .failure(ReplyError(.other, "write refused")) : base.write(a, v)
    }
    func delete(_ a: String) -> Result<Void, ReplyError> { base.delete(a) }
}

extension Reply {
    func isFault(_ f: Fault) -> Bool { if case .failed(f, _) = self { true } else { false } }
    var isInvalid: Bool { isFault(.invalid) }
    var message: String { if case let .failed(_, m) = self { m } else { "" } }
}
