import CairnFrame
import Foundation
import Security

// Secrets in the Keychain (docs/effects.md, "Secrets in the Keychain"): a request's secret
// header can come from a Keychain item, a 2xx JSON reply's top-level string fields can be
// captured into items and blanked before Lean sees the body, and `forgetSecret` deletes an item.
// Trusted: claims ^972 and ^973 in docs/trusted.md. The host knows nothing about any service: Lean
// names the items, the fields and the request; the host only stores, attaches and captures.
//
// A value never leaves this file and UploadEffects.swift except in a request's header or into
// the store: it is not in a reply, a message, a frame or a log.

/// Where Keychain secrets live: generic password items by account. Values are UTF-8 text.
public protocol SecretStore: Sendable {
    /// The item's value, or nil when there is none.
    func read(_ account: String) -> Result<String?, ReplyError>
    /// Create or replace the item.
    func write(_ account: String, _ value: String) -> Result<Void, ReplyError>
    /// Delete the item; success when there is none.
    func delete(_ account: String) -> Result<Void, ReplyError>
}

/// A store in memory: for tests, and for `Devices.inert`.
public final class MemoryStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String]

    public init(_ items: [String: String] = [:]) { self.items = items }

    public var snapshot: [String: String] { lock.withLock { items } }

    public func read(_ account: String) -> Result<String?, ReplyError> { .success(lock.withLock { items[account] }) }
    public func write(_ account: String, _ value: String) -> Result<Void, ReplyError> {
        lock.withLock { items[account] = value }
        return .success(())
    }
    public func delete(_ account: String) -> Result<Void, ReplyError> {
        lock.withLock { items[account] = nil }
        return .success(())
    }
}

/// The login keychain: generic password items with service `service` (the app's bundle
/// identifier) and the request's account. The file-based keychain, not the data-protection one:
/// that needs a provisioning profile and a keychain access group, which development builds and
/// `swift run` don't have (docs/trusted.md, "The Keychain keeps what it was given"). Never
/// synchronized to iCloud, no access group.
public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String) { self.service = service }

    /// The app's own items: the bundle identifier, or `cairn.<process name>` for an executable
    /// run outside a bundle.
    public static var app: KeychainStore {
        KeychainStore(service: Bundle.main.bundleIdentifier ?? "cairn." + ProcessInfo.processInfo.processName)
    }

    /// The query naming exactly one item: this service, this account.
    func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: kCFBooleanFalse as Any, kSecUseDataProtectionKeychain: kCFBooleanFalse as Any]
    }

    /// A failure, with the status's number and Security's text for it (never the value).
    func failure(_ status: OSStatus, _ what: String) -> ReplyError {
        let text = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
        let f: Fault = switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecNoAccessForItem: .denied
        default: .other
        }
        return ReplyError(f, "Keychain \(what) failed (\(status)) \(text)")
    }

    public func read(_ account: String) -> Result<String?, ReplyError> {
        var q = query(account)
        q[kSecReturnData] = kCFBooleanTrue
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return .success(nil) }
        guard st == errSecSuccess else { return .failure(failure(st, "read")) }
        guard let d = out as? Data, let s = String(data: d, encoding: .utf8) else {
            return .failure(ReplyError(.invalid, "the Keychain item \(account) is not UTF-8 text"))
        }
        return .success(s)
    }

    public func write(_ account: String, _ value: String) -> Result<Void, ReplyError> {
        let data = Data(value.utf8)
        var add = query(account)
        add[kSecValueData] = data
        add[kSecAttrLabel] = "\(service) (\(account))"
        var st = SecItemAdd(add as CFDictionary, nil)
        if st == errSecDuplicateItem {
            if data.isEmpty {
                // The file-based keychain answers success to an update with empty data and keeps
                // the old value (found by the fuzzer, ^972): replace the item instead.
                st = SecItemDelete(query(account) as CFDictionary)
                if st == errSecSuccess { st = SecItemAdd(add as CFDictionary, nil) }
            } else {
                st = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
            }
        }
        return st == errSecSuccess ? .success(()) : .failure(failure(st, "write"))
    }

    public func delete(_ account: String) -> Result<Void, ReplyError> {
        let st = SecItemDelete(query(account) as CFDictionary)
        return st == errSecSuccess || st == errSecItemNotFound ? .success(()) : .failure(failure(st, "delete"))
    }
}

/// Request-level rules for accounts: Lean names them; an empty one names no item.
enum Accounts {
    static func check(_ account: String) -> ReplyError? {
        account.isEmpty || account.utf8.contains(0) ? ReplyError(.invalid, "a Keychain account must be non-empty, without NUL") : nil
    }
}

/// `forgetSecret`.
public enum ForgetSecret {
    public static func run(_ account: String, _ store: SecretStore) -> Reply {
        if let e = Accounts.check(account) { return e.reply }
        switch store.delete(account) {
        case .success: return .done
        case let .failure(e): return e.reply
        }
    }
}

/// The capture of a 2xx JSON reply's top-level string fields (`Request.http`'s `capture`).
public enum JSONCapture {
    /// One top-level member: its decoded key, and the byte range of its value.
    struct Member { var key: String; var value: Range<Int>; var isString: Bool }

    /// The values of the listed fields, in capture order, and the body with each of those
    /// values written as `""`; or `failed invalid` when the body isn't a JSON object or a field
    /// is missing, repeated or not a string. Pure: nothing is written.
    public static func extract(_ body: [UInt8], _ captures: [Capture]) -> Result<(values: [String], body: [UInt8]), ReplyError> {
        guard (try? JSONSerialization.jsonObject(with: Data(body))) is [String: Any],
              let members = scan(body) else {
            return .failure(ReplyError(.invalid, "capture: the reply is not a JSON object"))
        }
        var values: [String] = [], blank: [Range<Int>] = []
        for c in captures {
            let ms = members.filter { $0.key == c.field }
            guard ms.count == 1 else {
                return .failure(ReplyError(.invalid, "capture: the reply has \(ms.isEmpty ? "no" : "a repeated") field \(c.field)"))
            }
            guard ms[0].isString, let v = decodeString(body[ms[0].value]) else {
                return .failure(ReplyError(.invalid, "capture: the field \(c.field) is not a string"))
            }
            values.append(v)
            if !blank.contains(ms[0].value) { blank.append(ms[0].value) }
        }
        var out: [UInt8] = [], at = 0
        for r in blank.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            out += body[at..<r.lowerBound]
            out += [0x22, 0x22]
            at = r.upperBound
        }
        out += body[at...]
        return .success((values, out))
    }

    static func decodeString(_ literal: ArraySlice<UInt8>) -> String? {
        try? JSONSerialization.jsonObject(with: Data(literal), options: .fragmentsAllowed) as? String
    }

    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    /// The members of the top-level object in UTF-8 JSON text, or nil if it isn't one. Only
    /// finds where things are: JSONSerialization has already checked the text is valid JSON.
    static func scan(_ b: [UInt8]) -> [Member]? {
        var i = 0
        func ws() { while i < b.count, isSpace(b[i]) { i += 1 } }
        /// Past a string starting at `i` (a quote); false if it never closes.
        func string() -> Bool {
            guard i < b.count, b[i] == 0x22 else { return false }
            i += 1
            while i < b.count {
                switch b[i] {
                case 0x5C: i += 2
                case 0x22: i += 1; return true
                default: i += 1
                }
            }
            return false
        }
        /// Past any value starting at `i`.
        func value() -> Bool {
            guard i < b.count else { return false }
            switch b[i] {
            case 0x22: return string()
            case 0x7B, 0x5B:
                var depth = 0
                while i < b.count {
                    switch b[i] {
                    case 0x22: if !string() { return false }; continue
                    case 0x7B, 0x5B: depth += 1
                    case 0x7D, 0x5D:
                        depth -= 1
                        if depth == 0 { i += 1; return true }
                    default: break
                    }
                    i += 1
                }
                return false
            default:
                let start = i
                while i < b.count, !isSpace(b[i]), b[i] != 0x2C, b[i] != 0x7D, b[i] != 0x5D { i += 1 }
                return i > start
            }
        }
        ws()
        guard i < b.count, b[i] == 0x7B else { return nil }
        i += 1
        var out: [Member] = []
        ws()
        if i < b.count, b[i] == 0x7D {
            i += 1
        } else {
            while true {
                ws()
                let k0 = i
                guard string(), let key = decodeString(b[k0..<i]) else { return nil }
                ws()
                guard i < b.count, b[i] == 0x3A else { return nil }
                i += 1
                ws()
                let v0 = i
                guard value() else { return nil }
                out.append(Member(key: key, value: v0..<i, isString: b[v0] == 0x22))
                ws()
                guard i < b.count else { return nil }
                if b[i] == 0x2C { i += 1; continue }
                guard b[i] == 0x7D else { return nil }
                i += 1
                break
            }
        }
        ws()
        return i == b.count ? out : nil
    }

    /// Writes every value to its item, all or nothing: if a write fails, the items written before
    /// it get their earlier values back (or are deleted if they had none).
    static func store(_ captures: [Capture], _ values: [String], _ store: SecretStore) -> ReplyError? {
        var before: [(String, String?)] = []
        for (c, v) in zip(captures, values) {
            let old: String?
            switch store.read(c.account) {
            case let .success(o): old = o
            case let .failure(e): undo(before, store); return e
            }
            if case let .failure(e) = store.write(c.account, v) { undo(before, store); return e }
            before.append((c.account, old))
        }
        return nil
    }

    static func undo(_ written: [(String, String?)], _ store: SecretStore) {
        for (a, old) in written.reversed() {
            if let old { _ = store.write(a, old) } else { _ = store.delete(a) }
        }
    }
}

/// `http` with its secret and captures: resolves the secret into its header (a missing one
/// answers `failed notFound` and sends nothing), runs the request as `HTTP.run` does, and on a
/// 2xx reply with captures stores the fields and blanks them.
public enum SecretHTTP {
    public static func run(method: String, url: String, headers: [Header], body: [UInt8], timeoutMs: UInt32,
                           secret: Secret?, capture: [Capture], secrets: SecretSource, session: URLSession,
                           _ reply: @escaping @Sendable (Reply) -> Void) {
        for c in capture {
            if let e = Accounts.check(c.account) { reply(e.reply); return }
        }
        var hs = headers
        if let secret {
            switch secrets.header(secret) {
            case let .success(h): hs.append(h)
            case let .failure(e): reply(e.reply); return
            }
        }
        let store = secrets.store
        HTTP.run(method: method, url: url, headers: hs, body: body, timeoutMs: timeoutMs, session: session,
                 followRedirects: secret == nil) { r in
            guard !capture.isEmpty, case let .http(status, rhs, rbody) = r, (200..<300).contains(status) else {
                reply(r)
                return
            }
            switch JSONCapture.extract(rbody, capture) {
            case let .failure(e): reply(e.reply)
            case let .success((values, blanked)):
                if let e = JSONCapture.store(capture, values, store) { reply(e.reply); return }
                reply(.http(status: status, headers: rhs, body: blanked))
            }
        }
    }
}
