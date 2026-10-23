import CairnFrame

/// The canonical dump of docs/frame.md, matching `Cairn.Dump` in Lean line for line. Strings
/// print printable ASCII as itself and every other scalar, `"` and `\` as `\u{HEX}`.
enum Dump {
    static func str(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            if u.value >= 0x20, u.value <= 0x7e, u != "\"", u != "\\" { out.unicodeScalars.append(u) }
            else { out += "\\u{\(String(u.value, radix: 16, uppercase: true))}" }
        }
        return out + "\""
    }

    static func rect(_ r: Rect) -> String { "\(r.x) \(r.y) \(r.w) \(r.h)" }
    static func color(_ c: Color) -> String { "\(c.r),\(c.g),\(c.b),\(c.a)" }
    static func ref(_ c: ControlRef) -> String { "\(c.claim)#\(c.key)" }
    static func bit(_ b: Bool) -> String { b ? "1" : "0" }
    static func opt<T>(_ v: T?, _ f: (T) -> String) -> String { v.map(f) ?? "none" }

    static func draw(_ d: Draw) -> String {
        switch d {
        case let .rect(r, fill, radius, border):
            return "rect \(rect(r)) fill=\(opt(fill, color)) radius=\(radius) border="
                + opt(border) { "\($0.width):\(color($0.color))" }
        case let .text(o, f, c, s):
            return "text \(o.x) \(o.y) font=\(f.family),\(f.size),\(f.weight),\(bit(f.italic)) "
                + "color=\(color(c)) \(str(s))"
        case let .pushClip(r): return "push \(rect(r))"
        case .popClip: return "pop"
        }
    }

    static func ax(_ n: AxNode) -> String {
        "node role=\(n.role.rawValue) control=\(opt(n.control, ref)) parent=\(opt(n.parent) { "\($0)" }) "
            + "rect=\(rect(n.rect)) focused=\(bit(n.focused)) selected=\(bit(n.selected)) "
            + "checked=\(opt(n.checked, bit)) label=\(str(n.label)) value=\(str(n.value))"
    }

    static func frame(_ f: Frame) -> String {
        var out = "frame \(f.size.w) \(f.size.h)\ndraws \(f.draws.count)\n"
        for d in f.draws { out += draw(d) + "\n" }
        out += "ax \(f.ax.count)\n"
        for n in f.ax { out += ax(n) + "\n" }
        if let t = f.textInput {
            out += "textInput control=\(ref(t.control)) rect=\(rect(t.rect)) caret=\(rect(t.caret)) "
                + "selection=\(t.selection.start) \(t.selection.end) "
                + "marked=\(opt(t.marked) { "\($0.start) \($0.end)" }) "
                + "origin=\(t.textOrigin.x) \(t.textOrigin.y) text=\(str(t.text))\n"
        } else {
            out += "textInput none\n"
        }
        out += "cursor \(f.cursor.rawValue)\neffects \(f.effects.count)\n"
        for e in f.effects {
            switch e {
            case let .setClipboard(s): out += "clipboard \(str(s))\n"
            case .beep: out += "beep\n"
            case let .focus(c): out += "focus \(ref(c))\n"
            }
        }
        return out
    }

    static func range(_ r: ScalarRange?) -> String { opt(r) { "\($0.start) \($0.end)" } }

    static func event(_ e: Event) -> String {
        switch e {
        case let .pointerMove(p): return "move \(p.x) \(p.y)"
        case let .pointerDown(p, b, c, m): return "down \(p.x) \(p.y) \(b.rawValue) \(c) \(m.code)"
        case let .pointerUp(p, b, m): return "up \(p.x) \(p.y) \(b.rawValue) \(m.code)"
        case .pointerExit: return "exit"
        case let .scroll(p, dx, dy): return "scroll \(p.x) \(p.y) \(dx) \(dy)"
        case let .key(k, m): return "key \(k.code) \(k.scalar) \(m.code)"
        case let .insertText(s, r): return "insert \(str(s)) replace=\(range(r))"
        case let .setMarked(s, a, l, r): return "marked \(str(s)) \(a) \(l) replace=\(range(r))"
        case .unmark: return "unmark"
        case .copy: return "copy"
        case .cut: return "cut"
        case .selectAll: return "selectAll"
        case .undo: return "undo"
        case .redo: return "redo"
        case let .paste(s): return "paste \(str(s))"
        case let .resize(s): return "resize \(s.w) \(s.h)"
        case let .scale(p): return "scale \(p)"
        case let .windowFocus(b): return "focus \(bit(b))"
        }
    }

    static func events(_ es: [Event]) -> String {
        "events \(es.count)\n" + es.map { event($0) + "\n" }.joined()
    }
}

/// Reads an event dump back into events, so the Swift encoder can be compared byte for byte
/// with Lean's on the same values.
enum DumpParser {
    struct Bad: Error { var line: String }

    static func events(_ text: String) throws -> [Event] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        guard let first = lines.first, first.hasPrefix("events ") else { throw Bad(line: lines.first ?? "") }
        return try lines.dropFirst().map(event)
    }

    static func event(_ line: String) throws -> Event {
        var t = Tokens(line)
        let word = t.word()
        func i() throws -> Int32 { guard let v = Int32(t.word()) else { throw Bad(line: line) }; return v }
        func u() throws -> UInt32 { guard let v = UInt32(t.word()) else { throw Bad(line: line) }; return v }
        func u8() throws -> UInt8 { guard let v = UInt8(t.word()) else { throw Bad(line: line) }; return v }
        func mods() throws -> Mods {
            let m = try u8()
            return Mods(shift: m & 1 != 0, command: m & 2 != 0, option: m & 4 != 0, control: m & 8 != 0)
        }
        func button() throws -> Button {
            guard let b = Button(rawValue: try u8()) else { throw Bad(line: line) }; return b
        }
        func replace() throws -> ScalarRange? {
            let w = t.word()
            guard w.hasPrefix("replace=") else { throw Bad(line: line) }
            if w == "replace=none" { return nil }
            guard let a = UInt32(w.dropFirst(8)) else { throw Bad(line: line) }
            return ScalarRange(start: a, end: try u())
        }
        switch word {
        case "move": return .pointerMove(Point(x: try i(), y: try i()))
        case "down":
            let p = Point(x: try i(), y: try i())
            let b = try button()
            let c = try u()
            return .pointerDown(p, b, clicks: c, try mods())
        case "up":
            let p = Point(x: try i(), y: try i())
            let b = try button()
            return .pointerUp(p, b, try mods())
        case "exit": return .pointerExit
        case "scroll": return .scroll(Point(x: try i(), y: try i()), dx: try i(), dy: try i())
        case "key":
            let code = try u8()
            let scalar = try u()
            let keys: [Key] = [.enter, .escape, .tab, .backspace, .delete, .left, .right, .up, .down,
                               .home, .finish, .pageUp, .pageDown]
            let k: Key
            if code == 13 {
                guard let s = Unicode.Scalar(scalar) else { throw Bad(line: line) }
                k = .char(Character(s))
            } else if code < 13 { k = keys[Int(code)] } else { throw Bad(line: line) }
            return .key(k, try mods())
        case "insert":
            let s = try t.string()
            return .insertText(s, replacing: try replace())
        case "marked":
            let s = try t.string()
            let a = try u(), l = try u()
            return .setMarked(s, selStart: a, selLen: l, replacing: try replace())
        case "unmark": return .unmark
        case "copy": return .copy
        case "cut": return .cut
        case "selectAll": return .selectAll
        case "undo": return .undo
        case "redo": return .redo
        case "paste": return .paste(try t.string())
        case "resize": return .resize(Size(w: try i(), h: try i()))
        case "scale": return .scale(percent: try u())
        case "focus": return .windowFocus(try u8() == 1)
        default: throw Bad(line: line)
        }
    }

    struct Tokens {
        var rest: Substring.UnicodeScalarView
        init(_ s: String) { rest = Substring(s).unicodeScalars }

        mutating func word() -> String {
            while rest.first == " " { rest.removeFirst() }
            var w = String.UnicodeScalarView()
            while let c = rest.first, c != " " { w.append(c); rest.removeFirst() }
            return String(w)
        }

        /// A quoted string with `\u{HEX}` escapes.
        mutating func string() throws -> String {
            while rest.first == " " { rest.removeFirst() }
            guard rest.first == "\"" else { throw Bad(line: String(rest)) }
            rest.removeFirst()
            var out = String.UnicodeScalarView()
            while let c = rest.first {
                rest.removeFirst()
                if c == "\"" { return String(out) }
                if c == "\\" {
                    guard rest.first == "u" else { throw Bad(line: String(rest)) }
                    rest.removeFirst(); rest.removeFirst()  // u{
                    var hex = ""
                    while let h = rest.first, h != "}" { hex.unicodeScalars.append(h); rest.removeFirst() }
                    rest.removeFirst()
                    guard let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) else {
                        throw Bad(line: hex)
                    }
                    out.append(s)
                } else {
                    out.append(c)
                }
            }
            throw Bad(line: "unterminated string")
        }
    }
}
