import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Cairn package registry: a nextpm `cairn` registry (nextpm docs/adr/0005-cairn-kind.md).
/// One token serves all of it: Bearer for the API, the password of Basic auth for Lake (in
/// RESERVOIR_API_URL) and git (through `cairn credential`).
public struct Registry: Sendable {
    public var url: URL
    public var token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    /// The API base Lake reads as RESERVOIR_API_URL, with the token as its password, since Lake
    /// sends no other credential.
    public var reservoir: String {
        var parts = URLComponents(url: url.appending(path: "api/v1"), resolvingAgainstBaseURL: false)!
        parts.user = "cairn"
        parts.password = token
        return parts.string!
    }

    public func git(_ owner: String, _ name: String) -> String {
        url.appending(path: "git/\(owner)/\(name).git").absoluteString
    }

    // MARK: Credentials

    /// ~/.config/cairn/credentials: `url` and `token`, in cairn.toml's format, mode 0600.
    public static var file: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
            ?? URL(filePath: NSHomeDirectory()).appending(path: ".config")
        return base.appending(path: "cairn/credentials")
    }

    /// The registry from CAIRN_REGISTRY and CAIRN_TOKEN, else from `cairn login`, else none.
    public static func current(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Registry? {
        if let url = env["CAIRN_REGISTRY"].flatMap(URL.init(string:)), let token = env["CAIRN_TOKEN"] {
            return Registry(url: url, token: token)
        }
        guard let text = try? String(contentsOf: file, encoding: .utf8), let doc = try? Toml.parse(text),
              case .string(let url)? = doc["registry"]?["url"], case .string(let token)? = doc["registry"]?["token"],
              let parsed = URL(string: url)
        else { return nil }
        return Registry(url: parsed, token: token)
    }

    public func save() throws(CairnError) {
        let text = "[registry]\nurl = \(Toml.quote(url.absoluteString))\ntoken = \(Toml.quote(token))\n"
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: Self.file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try text.write(to: Self.file, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
        } catch { throw CairnError("couldn't write \(Self.file.path): \(error.localizedDescription)") }
    }

    // MARK: API

    public struct Config: Decodable, Sendable { public var kind: String; public var owner: String?; public var registry: String }

    public func config() async throws(CairnError) -> Config {
        let (data, _) = try await send("GET", "config.json")
        do { return try JSONDecoder().decode(Config.self, from: data) } catch { throw CairnError("\(url) isn't a Cairn registry") }
    }

    public func owner() async throws(CairnError) -> String {
        let config = try await config()
        guard config.kind == "cairn" else { throw CairnError("\(url) is a \(config.kind) registry, not a Cairn one") }
        guard let owner = config.owner else { throw CairnError("\(url) has no owner") }
        return owner
    }

    public struct Version: Decodable, Sendable {
        public var version: String
        public var revision: String
        public var yanked: Bool
    }

    /// Every published version of a package, yanked ones too, newest first; empty for a new package.
    public func versions(_ owner: String, _ name: String) async throws(CairnError) -> [Version] {
        struct Answer: Decodable { var data: [Version] }
        let (data, status) = try await send("GET", "api/v1/packages/\(owner)/\(name)/versions?yanked=true", allow: [404])
        if status == 404 { return [] }
        do { return try JSONDecoder().decode(Answer.self, from: data).data } catch { throw CairnError("the registry's versions of \(name) don't parse") }
    }

    /// Send a request with the token; fail with the registry's own message on an unexpected status.
    @discardableResult
    public func send(_ method: String, _ path: String, body: Data? = nil, type: String? = nil, allow: Set<Int> = []) async throws(CairnError) -> (Data, Int) {
        guard let target = URL(string: path, relativeTo: url.absoluteString.hasSuffix("/") ? url : url.appending(path: "")) else {
            throw CairnError("bad registry path \(path)")
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let type { request.setValue(type, forHTTPHeaderField: "content-type") }
        request.httpBody = body
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch {
            throw CairnError("\(method) \(target.absoluteString): \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || allow.contains(status) { return (data, status) }
        struct Failure: Decodable { struct Inner: Decodable { var message: String }; var error: Inner }
        let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? String(decoding: data.prefix(300), as: UTF8.self)
        throw CairnError("the registry answered \(status) to \(method) \(path): \(message)")
    }
}
