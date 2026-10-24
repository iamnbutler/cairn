import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Cairn package registry: one public registry, as crates.io is for Rust, served by nextpm's
/// `cairn` kind (nextpm docs/adr/0005-cairn-kind.md). Anyone reads it with no credential: the API,
/// the Reservoir index Lake reads, git, and the build cache. Only a write (publish, artifact
/// upload, yank) sends a token, as `Authorization: Bearer`.
public struct Registry: Sendable {
    /// The public registry. CAIRN_REGISTRY overrides it, for a local nextpm or a stand-in.
    public static let standard = URL(string: "https://cairn.registry.nexthub.sh")!

    /// Send a request and return its body and response; URLSession unless a test swaps it.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public var url: URL
    /// The token `cairn login` saved for this registry, or CAIRN_TOKEN. Only writes send it.
    public var token: String?
    public var transport: Transport

    public init(url: URL = Registry.standard, token: String? = nil, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.url = url
        self.token = token
        self.transport = transport
    }

    /// The API base Lake reads as RESERVOIR_API_URL. No userinfo: reads need no credential.
    public var reservoir: String { url.appending(path: "api/v1").absoluteString }

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

    /// The registry: CAIRN_REGISTRY, else the public one. Its token is CAIRN_TOKEN, else the one
    /// `cairn login` saved for this same registry, else none; a token saved for another registry
    /// is never sent here.
    public static func current(_ env: [String: String] = ProcessInfo.processInfo.environment, saved: URL = Registry.file) -> Registry {
        let url = env["CAIRN_REGISTRY"].flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? standard
        if let token = env["CAIRN_TOKEN"], !token.isEmpty { return Registry(url: url, token: token) }
        guard let text = try? String(contentsOf: saved, encoding: .utf8), let doc = try? Toml.parse(text),
              case .string(let at)? = doc["registry"]?["url"], case .string(let token)? = doc["registry"]?["token"],
              same(URL(string: at), url)
        else { return Registry(url: url) }
        return Registry(url: url, token: token)
    }

    static func same(_ a: URL?, _ b: URL) -> Bool {
        let trim = { (u: URL) in u.absoluteString.hasSuffix("/") ? String(u.absoluteString.dropLast()) : u.absoluteString }
        return a.map(trim) == trim(b)
    }

    public func save(to file: URL = Registry.file) throws(CairnError) {
        guard let token else { throw CairnError("no token to save") }
        let text = "[registry]\nurl = \(Toml.quote(url.absoluteString))\ntoken = \(Toml.quote(token))\n"
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try text.write(to: file, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw CairnError("couldn't write \(file.path): \(error.localizedDescription)") }
    }

    // MARK: API

    /// `config.json`: `{kind, api, git, registry}`.
    public struct Config: Decodable, Sendable { public var kind: String; public var registry: String }

    /// Check that the URL is a Cairn registry.
    public func config() async throws(CairnError) -> Config {
        let (data, _) = try await send("GET", "config.json")
        guard let config = try? JSONDecoder().decode(Config.self, from: data) else { throw CairnError("\(url.absoluteString) isn't a Cairn registry") }
        guard config.kind == "cairn" else { throw CairnError("\(url.absoluteString) is a \(config.kind) registry, not a Cairn one") }
        return config
    }

    /// The login the token belongs to (nextpm's `GET /-/whoami`): a user's name, or an Org's for
    /// an Org token. `cairn publish` publishes under it unless `--owner` says otherwise.
    public func whoami() async throws(CairnError) -> String {
        struct Answer: Decodable { var username: String }
        let (data, status) = try await send("GET", "-/whoami", write: true, allow: [401])
        if status == 401 { throw CairnError("\(url.absoluteString) doesn't accept this token; `cairn login` with a nexthub token that has package:write") }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw CairnError("the registry's whoami answer doesn't parse") }
        return answer.username
    }

    /// The owner of a package, which its first publish fixed. The API reads a package only by
    /// `<owner>/<name>`, and a name has one owner, which `GET /api/v1/names/<name>` answers; nil
    /// for a name the registry doesn't hold (404).
    public func owner(of name: String) async throws(CairnError) -> String? {
        guard Names.valid(name) else { return nil }
        struct Answer: Decodable { struct Found: Decodable { var owner: String }; var data: Found }
        let (data, status) = try await send("GET", "api/v1/names/\(name)", allow: [404])
        if status == 404 { return nil }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw CairnError("the registry's answer for the name \(name) doesn't parse") }
        return answer.data.owner
    }

    public struct Version: Decodable, Sendable {
        public var version: String
        public var revision: String
        public var yanked: Bool

        enum Keys: String, CodingKey { case version, revision, yanked }

        /// Lean's Reservoir, which the registry passes a name it lacks to, says nothing of yanking.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            version = try c.decode(String.self, forKey: .version)
            revision = try c.decode(String.self, forKey: .revision)
            yanked = try c.decodeIfPresent(Bool.self, forKey: .yanked) ?? false
        }
    }

    /// Every published version of a package, yanked ones too, newest first; empty for a name
    /// nobody holds under `owner`.
    public func versions(_ owner: String, _ name: String) async throws(CairnError) -> [Version] {
        struct Answer: Decodable { var data: [Version] }
        let (data, status) = try await send("GET", "api/v1/packages/\(owner)/\(name)/versions?yanked=true", allow: [404])
        if status == 404 { return [] }
        do { return try JSONDecoder().decode(Answer.self, from: data).data } catch { throw CairnError("the registry's versions of \(name) don't parse") }
    }

    /// Send a request; fail with the registry's own message on an unexpected status. Only a
    /// `write` sends the token, and a write with no token fails before it is sent.
    @discardableResult
    public func send(_ method: String, _ path: String, body: Data? = nil, type: String? = nil, write: Bool = false, allow: Set<Int> = []) async throws(CairnError) -> (Data, Int) {
        guard let target = URL(string: path, relativeTo: url.absoluteString.hasSuffix("/") ? url : url.appending(path: "")) else {
            throw CairnError("bad registry path \(path)")
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        if write {
            guard let token else { throw CairnError("publishing needs a token: `cairn login` with a nexthub token that has package:write, or set CAIRN_TOKEN") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let type { request.setValue(type, forHTTPHeaderField: "content-type") }
        request.httpBody = body
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) } catch {
            throw CairnError("\(method) \(target.absoluteString): \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || allow.contains(status) { return (data, status) }
        struct Failure: Decodable { struct Inner: Decodable { var message: String }; var error: Inner }
        let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? String(decoding: data.prefix(300), as: UTF8.self)
        throw CairnError("the registry answered \(status) to \(method) \(path): \(message)")
    }
}
