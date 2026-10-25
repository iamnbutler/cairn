import CairnFrame
import Foundation

// The `upload` request (docs/effects.md): HTTP whose body is assembled from Lean's bytes and
// the host's recordings, with one header whose value is a secret the host reads as it sends.
// Trusted: claims ^970 and ^976 in docs/trusted.md (and ^972 for Keychain secrets). Lean builds the multipart body itself
// (boundary, part headers) as `bytes` parts around a `wav` part; the host only splices.
//
// The secret's value never leaves this file except in the request's header: it is not in a
// reply, a message, a frame or a log.

/// Where secrets come from: for an environment secret the environment, then a `KEY=value`
/// file (Yap's Secrets); for a Keychain secret the store (SecretEffects.swift).
public struct SecretSource: Sendable {
    public var environment: @Sendable (String) -> String?
    /// The file's text, or nil when it can't be read.
    public var readFile: @Sendable (String) -> String?
    /// The app's Keychain items.
    public var store: any SecretStore

    public init(environment: @escaping @Sendable (String) -> String?, readFile: @escaping @Sendable (String) -> String?,
                store: any SecretStore = MemoryStore()) {
        self.environment = environment
        self.readFile = readFile
        self.store = store
    }

    public static let live = SecretSource(
        environment: { ProcessInfo.processInfo.environment[$0] },
        readFile: { path in
            guard Files.invalid(path) == nil else { return nil }
            return try? String(contentsOfFile: Files.expand(path), encoding: .utf8)
        },
        store: KeychainStore.app)

    /// The secret's value. An environment secret: the variable if set and not empty, else the
    /// file's line for it. A Keychain secret: the item. A missing secret is `failed notFound`,
    /// naming where it looked (never a value).
    public func resolve(_ s: Secret) -> Result<String, ReplyError> {
        switch s.source {
        case let .env(file, name):
            if let v = environment(name), !v.isEmpty { return .success(v) }
            if let text = readFile(file), let v = Self.parseDotEnv(text)[name], !v.isEmpty { return .success(v) }
            // Yap's `Secrets.MissingKey` text, with the file's full path.
            return .failure(ReplyError(.notFound, "No \(name) in the environment or \(Files.expand(file))"))
        case let .keychain(account):
            if let e = Accounts.check(account) { return .failure(e) }
            switch store.read(account) {
            case let .success(v?): return .success(v)
            case .success(nil): return .failure(ReplyError(.notFound, "No Keychain item \(account)"))
            case let .failure(e): return .failure(e)
            }
        }
    }

    /// The header the secret adds, `header: scheme ++ value`; `failed invalid` when that would
    /// have a line break or NUL (no header injection).
    public func header(_ s: Secret) -> Result<Header, ReplyError> {
        resolve(s).flatMap { v in
            (s.scheme + v).utf8.contains(where: { $0 == 0x0D || $0 == 0x0A || $0 == 0 })
                ? .failure(ReplyError(.invalid, "the secret \(s.label) has a line break or NUL"))
                : .success(Header(s.header, s.scheme + v))
        }
    }

    /// Yap's `Secrets.parseDotEnv`: `KEY=value` lines, `#` comments, an optional `export `,
    /// optional matching quotes around the value; a later line wins.
    public static func parseDotEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let sep = line.firstIndex(of: "=") else { continue }
            let key = line[..<sep].replacingOccurrences(of: "export ", with: "").trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}

public enum Upload {
    /// The body: each part in order, a `wav` part as the clip's WAV file for those windows.
    public static func body(_ parts: [Part], _ clips: Clips, wait: Double = 1) -> Result<[UInt8], ReplyError> {
        var out: [UInt8] = []
        for p in parts {
            switch p {
            case let .bytes(b): out += b
            case let .wav(clip, start, stop):
                switch clips.wav(clip, start: start, stop: stop, wait: wait) {
                case let .success(w): out += w
                case let .failure(e): return .failure(e)
                }
            }
        }
        guard out.count <= Int(UInt32.max) else { return .failure(ReplyError(.invalid, "body too large")) }
        return .success(out)
    }

    /// Assembles the body, resolves the secret into its header (`scheme ++ value`), then runs
    /// it as `http` does. Any failure before sending is a reply and sends nothing.
    public static func run(method: String, url: String, headers: [Header], secret: Secret?, body parts: [Part],
                           timeoutMs: UInt32, clips: Clips, secrets: SecretSource, session: URLSession,
                           _ reply: @escaping @Sendable (Reply) -> Void) {
        let body: [UInt8]
        switch Self.body(parts, clips) {
        case let .success(b): body = b
        case let .failure(e): reply(e.reply); return
        }
        var hs = headers
        if let secret {
            switch secrets.header(secret) {
            case let .success(h): hs.append(h)
            case let .failure(e): reply(e.reply); return
            }
        }
        HTTP.run(method: method, url: url, headers: hs, body: body, timeoutMs: timeoutMs, session: session,
                 followRedirects: secret == nil, reply)
    }
}
