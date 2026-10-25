import Foundation

/// Lake's git dependencies on the registry's dumb HTTP (#196). Lake fetches every git dependency
/// as a partial clone (`--filter=tree:0`), so `origin` is a promisor remote. Over dumb HTTP git's
/// object walker lazy-fetches each object it is about to fetch, from the same remote, without end.
/// `GIT_NO_LAZY_FETCH=1` stops that, but it breaks smart-HTTP (GitHub) dependencies, whose checkout
/// needs lazy fetches. So `cairn` sets it for Lake only when every git dependency is on a registry,
/// and before Lake runs it fetches, with lazy fetches off, each registry dependency's manifest
/// commit that its checkout lacks. The real fix is smart HTTP on the registry.
public struct LakeManifest: Equatable, Sendable {
    public struct Git: Equatable, Sendable {
        public var name: String
        public var url: String
        public var rev: String
    }

    /// Where Lake checks dependencies out, relative to the Lake package.
    public var packagesDir = ".lake/packages"
    /// Every package of the workspace, direct or inherited.
    public var names: [String] = []
    /// The git ones.
    public var git: [Git] = []

    /// lake-manifest.json's text, or nil if it isn't one.
    public static func parse(_ data: Data) -> LakeManifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = json["packages"] as? [[String: Any]] else { return nil }
        var out = LakeManifest()
        if let dir = json["packagesDir"] as? String { out.packagesDir = dir }
        for p in packages {
            guard let name = p["name"] as? String else { continue }
            out.names.append(name)
            if p["type"] as? String == "git", let url = p["url"] as? String, let rev = p["rev"] as? String {
                out.git.append(Git(name: name, url: url, rev: rev))
            }
        }
        return out
    }

    /// The manifest of the Lake package in `lean`, if it has one.
    public static func load(_ lean: URL) -> LakeManifest? {
        (try? Data(contentsOf: lean.appending(path: "lake-manifest.json"))).flatMap(parse)
    }
}

public enum LazyFetch {
    /// Whether `url` is a git repository on one of `registries` (`<registry>/git/<owner>/<name>.git`).
    public static func served(_ url: String, by registries: [URL]) -> Bool {
        registries.contains { url.hasPrefix(Registry.trim($0) + "/git/") }
    }

    /// Whether Lake can run with `GIT_NO_LAZY_FETCH=1`: the manifest names every package the
    /// lakefile requires (so Lake won't resolve one it doesn't list), every git package is on a
    /// registry, and the lakefile names no other git URL. With no manifest, Lake resolves from
    /// scratch, perhaps from GitHub, so no.
    public static func safe(_ manifest: LakeManifest?, lakefile: Lakefile?, registries: [URL]) -> Bool {
        guard let manifest, let lakefile else { return false }
        guard manifest.git.allSatisfy({ served($0.url, by: registries) }) else { return false }
        guard lakefile.requires.allSatisfy(manifest.names.contains) else { return false }
        return lakefile.urls.allSatisfy { served($0, by: registries) }
    }

    /// The registries whose git URLs count: the one in use, and the public one.
    static func registries(_ registry: Registry) -> [URL] {
        Registry.same(registry.url, Registry.standard) ? [registry.url] : [registry.url, Registry.standard]
    }

    static let off = ["GIT_NO_LAZY_FETCH": "1"]

    /// Fetch, with lazy fetches off, each registry dependency's manifest commit that its checkout
    /// lacks, so Lake finds it there and never fetches over dumb HTTP itself. A failure only
    /// warns: Lake then fetches as it would have. Returns the names fetched.
    @discardableResult
    static func prefetch(_ manifest: LakeManifest, lean: URL, registries: [URL], shell: Shell) -> [String] {
        var fetched: [String] = []
        for dep in manifest.git where served(dep.url, by: registries) {
            let dir = lean.appending(path: manifest.packagesDir).appending(path: dep.name)
            guard FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) else { continue }
            // Lake re-clones a checkout whose origin isn't the manifest's URL; leave that to it.
            guard let origin = try? shell.capture(["git", "remote", "get-url", "origin"], in: dir, check: false),
                  origin.status == 0, served(origin.text, by: registries) else { continue }
            // With lazy fetches off, so a missing commit is an answer and not a fetch.
            let has = try? shell.capture(["git", "rev-parse", "--verify", "-q", "\(dep.rev)^{commit}"], in: dir, env: off, check: false)
            if has?.status == 0 { continue }
            // Only a checkout Lake made (it has a commit): in an empty repository, a dumb-HTTP
            // fetch of a bare commit id without --tags spins in git-remote-https.
            let head = try? shell.capture(["git", "rev-parse", "-q", "--verify", "HEAD^{commit}"], in: dir, env: off, check: false)
            guard head?.status == 0 else { continue }
            do {
                try shell.run(["git", "fetch", "-q", "origin", dep.rev], in: dir, env: off)
                fetched.append(dep.name)
            } catch {
                FileHandle.standardError.write(Data("cairn: couldn't prefetch \(dep.name) \(dep.rev) (\(error.description)); Lake will fetch it\n".utf8))
            }
        }
        return fetched
    }
}

extension Registry {
    static func trim(_ u: URL) -> String {
        u.absoluteString.hasSuffix("/") ? String(u.absoluteString.dropLast()) : u.absoluteString
    }
}

extension Lakefile {
    /// The names of the packages the lakefile requires.
    public var requires: [String] {
        switch format {
        case .lean:
            // `require cairn …`, `require "cairn" …`, `require «cairn» …`, `require "owner" / "cairn" …`
            let name = #"(?:"([^"]+)"|«([^»]+)»|([A-Za-z_][A-Za-z0-9_-]*))"#
            let pattern = try! Regex("(?m)^require\\s+(?:\(name)\\s*/\\s*)?\(name)")
            return text.matches(of: pattern).compactMap { m in
                (4...6).lazy.compactMap { m.output[$0].substring.map(String.init) }.first
            }
        case .toml:
            var out: [String] = []
            var inRequire = false
            for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if line.hasPrefix("[") { inRequire = line == "[[require]]"; continue }
                if inRequire, let m = line.wholeMatch(of: /name\s*=\s*"([^"]*)"\s*(#.*)?/) { out.append(String(m.1)) }
            }
            return out
        }
    }

    /// The http(s) URLs the lakefile names in quotes: git requires' sources.
    public var urls: [String] {
        text.matches(of: /"(https?:\/\/[^"]+)"/).map { String($0.1) }
    }
}
