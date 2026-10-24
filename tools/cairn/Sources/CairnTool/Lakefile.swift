import Foundation

/// The parts of a Lake package's lakefile that `cairn` reads and writes: the package's name, its
/// claim scope, and the registry `require` of each dependency. Both lakefile.toml and
/// lakefile.lean, edited as text so the rest of the file stays as its author wrote it.
public struct Lakefile: Sendable {
    public enum Format: Sendable { case toml, lean }
    public var format: Format
    public var text: String

    public init(format: Format, text: String) {
        self.format = format
        self.text = text
    }

    /// The lakefile in `dir`, preferring lakefile.lean as Lake does.
    public static func load(_ dir: URL) throws(CairnError) -> (Lakefile, URL) {
        for (file, format) in [("lakefile.lean", Format.lean), ("lakefile.toml", .toml)] {
            let url = dir.appending(path: file)
            if let text = try? String(contentsOf: url, encoding: .utf8) { return (Lakefile(format: format, text: text), url) }
        }
        throw CairnError("no lakefile.lean or lakefile.toml in \(dir.path)")
    }

    /// The Lake package's name: `name = "…"` before any table, or `package <name>`.
    public var name: String? {
        switch format {
        case .toml:
            for line in text.split(separator: "\n") {
                if line.hasPrefix("[") { return nil }
                if let m = line.wholeMatch(of: /\s*name\s*=\s*"([^"]*)"\s*(#.*)?/) { return String(m.1) }
            }
            return nil
        case .lean:
            return text.firstMatch(of: /(?m)^package\s+(?:«([^»]+)»|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))/)
                .map { String($0.1 ?? $0.2 ?? $0.3 ?? "") }
        }
    }

    /// The value of the `cairn.claims.scope` option (with or without `weak.`), if the lakefile sets it.
    public var scope: String? {
        text.firstMatch(of: /cairn\.claims\.scope[`"]?\s*(?:,|=)\s*"([^"]*)"/).map { String($0.1) }
    }

    /// Require `dep` from the registry scope `owner` at `range`, replacing an existing require of it.
    public mutating func require(_ dep: String, owner: String, range: String) {
        switch format {
        case .lean:
            let line = "require \(Toml.quote(owner)) / \(Toml.quote(dep)) @ \(Toml.quote(range))"
            var lines = text.components(separatedBy: "\n")
            // `require cairn …`, `require "cairn" …`, `require "owner" / "cairn" …`, `require owner / cairn …`
            let pattern = try! Regex("^require\\s+(?:(?:\"[^\"]*\"|[A-Za-z_][A-Za-z0-9_-]*)\\s*/\\s*)?(?:\"\(dep)\"|«\(dep)»|\(dep))(?:\\s|$)")
            if let at = lines.firstIndex(where: { $0.firstMatch(of: pattern) != nil }) {
                lines[at] = line
                text = lines.joined(separator: "\n")
            } else if let at = lines.lastIndex(where: { $0.hasPrefix("require ") }) {
                lines.insert(line, at: at + 1)
                text = lines.joined(separator: "\n")
            } else if let at = lines.firstIndex(where: { $0.hasPrefix("package ") }) {
                // After the package declaration and its indented `where` block.
                var end = at + 1
                while end < lines.count, lines[end].hasPrefix(" ") || lines[end].hasPrefix("\t") { end += 1 }
                lines.insert(contentsOf: ["", line], at: end)
                text = lines.joined(separator: "\n")
            } else {
                text += (text.hasSuffix("\n") ? "" : "\n") + line + "\n"
            }
        case .toml:
            let block = ["[[require]]", "name = \(Toml.quote(dep))", "scope = \(Toml.quote(owner))", "version = \(Toml.quote(range))"]
            var lines = text.components(separatedBy: "\n")
            var at = 0
            while at < lines.count {
                guard lines[at].trimmingCharacters(in: .whitespaces) == "[[require]]" else { at += 1; continue }
                var end = at + 1
                while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
                let body = lines[(at + 1)..<end]
                if body.contains(where: { $0.wholeMatch(of: try! Regex("\\s*name\\s*=\\s*\"\(dep)\"\\s*")) != nil }) {
                    var trailing = Array(body.reversed().prefix { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    trailing.reverse()
                    lines.replaceSubrange(at..<end, with: block + trailing)
                    text = lines.joined(separator: "\n")
                    return
                }
                at = end
            }
            text += (text.hasSuffix("\n") ? "" : "\n") + "\n" + block.joined(separator: "\n") + "\n"
        }
    }
}
