import Foundation

/// What a package builds, as Cargo has it: a library that other packages depend on, or a binary
/// (an app, as the site calls it) that nothing can depend on. The registry refuses a dependency
/// on a `bin`.
public enum Kind: String, Sendable, CaseIterable {
    case lib, bin
}

/// A package's `cairn.toml` (docs/cli.md, "cairn.toml"). The name is the Lake package's name and
/// the claim scope, so `yap^301` reads the same in the code, the ledger and the registry.
public struct Manifest: Equatable, Sendable {
    public var name: String
    public var version: String
    /// `lib` or `bin`. A manifest from before kinds has none, and is a `lib`.
    public var kind = Kind.lib
    public var description: String?
    public var license: String?
    /// The Lake package's directory, relative to the repository root.
    public var lean = "lean"
    /// The Lean libraries that `cairn-link` merges into the app's static library.
    public var libs: [String] = []
    /// The directory of the SwiftPM package (its Package.swift), relative to the root.
    public var swift = "."
    public var claims = "claims.lock"
    /// Each dependency and its version range, in file order.
    public var dependencies: [(name: String, range: String)] = []

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public static func == (a: Manifest, b: Manifest) -> Bool {
        a.name == b.name && a.version == b.version && a.kind == b.kind && a.description == b.description
            && a.license == b.license && a.lean == b.lean && a.libs == b.libs && a.swift == b.swift
            && a.claims == b.claims && a.dependencies.map(\.name) == b.dependencies.map(\.name)
            && a.dependencies.map(\.range) == b.dependencies.map(\.range)
    }

    static let packageKeys: Set = ["name", "version", "kind", "description", "license", "lean", "libs", "swift", "claims"]

    /// Parse `cairn.toml`. Unknown tables and keys are errors, so a typo never goes unnoticed.
    public static func parse(_ text: String) throws(CairnError) -> Manifest {
        let doc = try Toml.parse(text)
        for table in doc.keys where table != "package" && table != "dependencies" {
            throw CairnError("cairn.toml: unknown table [\(table)]")
        }
        guard let pkg = doc["package"] else { throw CairnError("cairn.toml: missing [package]") }
        for (key, _) in pkg.entries where !packageKeys.contains(key) {
            throw CairnError("cairn.toml: unknown key `\(key)` in [package]")
        }
        func string(_ key: String) throws(CairnError) -> String? {
            switch pkg[key] {
            case nil: return nil
            case .string(let s)?: return s
            case .array?: throw CairnError("cairn.toml: `\(key)` must be a string")
            }
        }
        guard let name = try string("name") else { throw CairnError("cairn.toml: missing `name` in [package]") }
        guard let version = try string("version") else { throw CairnError("cairn.toml: missing `version` in [package]") }
        guard Names.valid(name) else {
            throw CairnError("cairn.toml: `\(name)` isn't a package name: lowercase letters, digits and _, starting with a letter, at most 64")
        }
        guard Names.version(version) else { throw CairnError("cairn.toml: `\(version)` isn't a version like 0.1.0 or 0.1.0-rc.1") }
        var out = Manifest(name: name, version: version)
        if let kind = try string("kind") {
            guard let known = Kind(rawValue: kind) else { throw CairnError("cairn.toml: `kind` is \"lib\" or \"bin\", not \"\(kind)\"") }
            out.kind = known
        }
        out.description = try string("description")
        out.license = try string("license")
        out.lean = try string("lean") ?? out.lean
        out.swift = try string("swift") ?? out.swift
        out.claims = try string("claims") ?? out.claims
        switch pkg["libs"] {
        case nil: break
        case .array(let list)?: out.libs = list
        case .string?: throw CairnError("cairn.toml: `libs` must be a list of strings")
        }
        for (dep, value) in doc["dependencies"]?.entries ?? [] {
            guard case .string(let range) = value else { throw CairnError("cairn.toml: dependency `\(dep)` needs a version range string") }
            guard Names.valid(dep) else { throw CairnError("cairn.toml: `\(dep)` isn't a package name") }
            guard Names.range(range) else { throw CairnError("cairn.toml: `\(range)` isn't a version range like ^0.1.0") }
            out.dependencies.append((dep, range))
        }
        return out
    }

    /// The file's text, in a fixed order; what `cairn new` and `cairn add` write.
    public func render() -> String {
        var lines = ["[package]", "name = \(Toml.quote(name))", "version = \(Toml.quote(version))", "kind = \(Toml.quote(kind.rawValue))"]
        if let description { lines.append("description = \(Toml.quote(description))") }
        if let license { lines.append("license = \(Toml.quote(license))") }
        if lean != "lean" { lines.append("lean = \(Toml.quote(lean))") }
        lines.append("libs = [\(libs.map(Toml.quote).joined(separator: ", "))]")
        if swift != "." { lines.append("swift = \(Toml.quote(swift))") }
        if claims != "claims.lock" { lines.append("claims = \(Toml.quote(claims))") }
        lines.append("")
        lines.append("[dependencies]")
        for dep in dependencies { lines.append("\(dep.name) = \(Toml.quote(dep.range))") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The libraries `cairn-link` links into an app that depends on this package. Cairn 0.1.2
    /// and earlier list none, and `cairn-link` linked their `Cairn` by name.
    public var linkedLibs: [String] {
        libs.isEmpty && name == "cairn" ? ["Cairn"] : libs
    }

    /// Add a dependency or change its range.
    public mutating func require(_ dep: String, _ range: String) {
        if let at = dependencies.firstIndex(where: { $0.name == dep }) {
            dependencies[at].range = range
        } else {
            dependencies.append((dep, range))
        }
    }
}

/// Package names and versions, as the registry checks them (nextpm's cairn kind, names.ts).
public enum Names {
    public static func valid(_ name: String) -> Bool {
        name.wholeMatch(of: /[a-z][a-z0-9_]{0,63}/) != nil
    }

    /// Strict semver, with an optional pre-release and no build metadata.
    public static func version(_ text: String) -> Bool {
        text.wholeMatch(of: /(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?/) != nil
    }

    /// A range Lake understands: `^x.y.z`, `~x.y.z`, `=x.y.z`, `>=x.y.z` or a bare version.
    public static func range(_ text: String) -> Bool {
        let bare = text.replacing(/^(\^|~|=|>=)/, with: "")
        return version(bare)
    }
}

/// A user-facing failure: its message is what `cairn` prints.
public struct CairnError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ message: String) { description = message }
}

/// The part of TOML that `cairn.toml` uses: `[table]`s of `key = "string"` and
/// `key = ["string", …]`, with `#` comments.
enum Toml {
    enum Value: Equatable { case string(String), array([String]) }

    struct Table {
        var entries: [(String, Value)] = []
        subscript(key: String) -> Value? { entries.first { $0.0 == key }?.1 }
    }

    struct Doc {
        var tables: [(String, Table)] = []
        var keys: [String] { tables.map(\.0) }
        subscript(name: String) -> Table? { tables.first { $0.0 == name }?.1 }
    }

    static func parse(_ text: String) throws(CairnError) -> Doc {
        var doc = Doc()
        for (at, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            let where_ = "cairn.toml line \(at + 1)"
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let m = line.wholeMatch(of: /\[([A-Za-z0-9_-]+)\]\s*(#.*)?/) {
                let name = String(m.1)
                if doc[name] != nil { throw CairnError("\(where_): [\(name)] appears twice") }
                doc.tables.append((name, Table()))
                continue
            }
            guard !doc.tables.isEmpty else { throw CairnError("\(where_): a key before any [table]") }
            guard let eq = line.firstIndex(of: "=") else { throw CairnError("\(where_): expected `key = value`") }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil else { throw CairnError("\(where_): `\(key)` isn't a bare key") }
            var rest = Substring(line[line.index(after: eq)...]).drop { $0 == " " || $0 == "\t" }
            let value: Value
            if rest.first == "[" {
                rest = rest.dropFirst()
                var items: [String] = []
                while true {
                    rest = rest.drop { $0 == " " || $0 == "\t" || $0 == "," }
                    if rest.first == "]" { rest = rest.dropFirst(); break }
                    guard rest.first == "\"" else { throw CairnError("\(where_): a list holds \"strings\" on one line") }
                    items.append(try string(&rest, where_))
                }
                value = .array(items)
            } else if rest.first == "\"" {
                value = .string(try string(&rest, where_))
            } else {
                throw CairnError("\(where_): values are \"strings\" or [\"lists\"]")
            }
            let tail = rest.trimmingCharacters(in: .whitespaces)
            guard tail.isEmpty || tail.hasPrefix("#") else { throw CairnError("\(where_): unexpected `\(tail)`") }
            let last = doc.tables.count - 1
            if doc.tables[last].1[key] != nil { throw CairnError("\(where_): `\(key)` appears twice") }
            doc.tables[last].1.entries.append((key, value))
        }
        return doc
    }

    /// A basic string at the start of `rest`, which it consumes.
    static func string(_ rest: inout Substring, _ where_: String) throws(CairnError) -> String {
        rest = rest.dropFirst()
        var out = ""
        while let c = rest.first {
            rest = rest.dropFirst()
            switch c {
            case "\"": return out
            case "\\":
                guard let e = rest.first else { break }
                rest = rest.dropFirst()
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: throw CairnError("\(where_): unknown escape \\\(e)")
                }
            default: out.append(c)
            }
        }
        throw CairnError("\(where_): unterminated string")
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
