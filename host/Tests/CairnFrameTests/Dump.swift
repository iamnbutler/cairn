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
            return "text \(o.x) \(o.y) font=\(f.family),\(f.size),\(f.weight),\(bit(f.italic)),"
                + "\(f.width.rawValue),\(f.tracking),\(bit(f.tabular)) color=\(color(c)) \(str(s))"
        case let .pushClip(r): return "push \(rect(r))"
        case .popClip: return "pop"
        case let .shape(r, fill, radius, border, corner, shadow):
            return "shape \(rect(r)) fill=\(opt(fill, color)) radius=\(radius) border="
                + opt(border) { "\($0.width):\(color($0.color))" }
                + " corner=\(corner.rawValue) shadow="
                + opt(shadow) { "\(color($0.color)):\($0.radius):\($0.x):\($0.y)" }
        case let .paint(r, p):
            func ints(_ xs: [Int32]) -> String { "[" + xs.map { "\($0)" }.joined(separator: ",") + "]" }
            return "paint \(rect(r)) origin=\(p.origin) shader=\(str(p.shader)) scalars=\(ints(p.scalars)) arrays=["
                + p.arrays.map(ints).joined(separator: ",") + "]"
        case let .image(r, d, src):
            return "image \(rect(r)) dest=\(rect(d)) \(str(src))"
        }
    }

    static func ax(_ n: AxNode) -> String {
        "node role=\(n.role.rawValue) control=\(opt(n.control, ref)) parent=\(opt(n.parent) { "\($0)" }) "
            + "rect=\(rect(n.rect)) focused=\(bit(n.focused)) selected=\(bit(n.selected)) "
            + "checked=\(opt(n.checked, bit)) secure=\(bit(n.secure)) menu=\(opt(n.menu, bit)) "
            + "label=\(str(n.label)) value=\(str(n.value))"
    }

    static func canvas(_ c: Canvas) -> String {
        var out = "canvas \(c.size.w) \(c.size.h)\ndraws \(c.draws.count)\n"
        for d in c.draws { out += draw(d) + "\n" }
        out += "ax \(c.ax.count)\n"
        for n in c.ax { out += ax(n) + "\n" }
        if let t = c.textInput {
            out += "textInput control=\(ref(t.control)) rect=\(rect(t.rect)) caret=\(rect(t.caret)) "
                + "selection=\(t.selection.start) \(t.selection.end) "
                + "marked=\(opt(t.marked) { "\($0.start) \($0.end)" }) "
                + "origin=\(t.textOrigin.x) \(t.textOrigin.y) secure=\(bit(t.secure)) text=\(str(t.text))\n"
        } else {
            out += "textInput none\n"
        }
        return out + "cursor \(c.cursor.rawValue)\n"
    }

    static func shortcut(_ s: Shortcut) -> String { "\(s.key.code),\(s.key.scalar),\(s.mods.code)" }

    static func menuRecord(_ m: MenuRecord) -> String {
        "item kind=\(m.kind.rawValue) control=\(opt(m.control, ref)) parent=\(opt(m.parent) { "\($0)" }) "
            + "place=\(opt(m.place) { "\($0)" }) enabled=\(bit(m.enabled)) checked=\(opt(m.checked, bit)) "
            + "shortcut=\(opt(m.shortcut, shortcut)) label=\(str(m.label))"
    }

    static func status(_ s: StatusFrame) -> String {
        var out = "status control=\(ref(s.control)) symbol=\(str(s.symbol)) title=\(str(s.title)) "
            + "label=\(str(s.label))\nmenu \(s.menu.count)\n"
        for m in s.menu { out += menuRecord(m) + "\n" }
        return out
    }

    static func surface(_ s: Surface) -> String {
        "surface kind=\(s.kind.rawValue) place=\(s.place) shown=\(bit(s.shown)) "
            + "anchor=\(s.anchor.code) offset=\(s.anchor.offset) screen=\(s.screen.rawValue) "
            + "min=\(s.minSize.w)x\(s.minSize.h) title=\(str(s.title))\n" + canvas(s.canvas) + status(s.status)
    }

    static func frame(_ f: Frame) -> String {
        var out = "frame\nsurfaces \(f.surfaces.count)\n"
        for s in f.surfaces { out += surface(s) }
        out += "effects \(f.effects.count)\n"
        for e in f.effects {
            switch e {
            case let .setClipboard(s): out += "clipboard \(str(s))\n"
            case .beep: out += "beep\n"
            case let .focus(c): out += "focus \(ref(c))\n"
            case let .setTimer(n, ms): out += "timer \(str(n)) \(ms)\n"
            case let .cancelTimer(n): out += "cancelTimer \(str(n))\n"
            case let .request(id, r): out += "request \(id) \(request(r))\n"
            case .quit: out += "quit\n"
            case let .cancelRequest(id): out += "cancelRequest \(id)\n"
            case let .scrollTo(c, t):
                let to = switch t { case .start: "start"; case .finish: "end"; case let .key(k): "key \(k)" }
                out += "scrollTo \(ref(c)) \(to)\n"
            case let .badge(l): out += "badge \(l.map(str) ?? "none")\n"
            case let .announce(t, p): out += "announce \(p == .high ? "high" : "low") \(str(t))\n"
            }
        }
        out += "subs \(f.subs.count)\n"
        for c in f.subs {
            switch c {
            case let .start(id, .every(ms)): out += "start \(id) every \(ms)\n"
            case let .start(id, .watchFile(p)): out += "start \(id) watchFile \(str(p))\n"
            case let .start(id, .record(c)): out += "start \(id) record \(c)\n"
            case let .start(id, .globalKey(code, m)): out += "start \(id) globalKey \(code) \(opt(m) { "\($0)" })\n"
            case let .start(id, .imageCache(n)): out += "start \(id) imageCache \(n)\n"
            case let .stop(id): out += "stop \(id)\n"
            }
        }
        out += "wake \(opt(f.wake) { "\($0)" })\n"
        return out
    }

    /// Bytes as `x` and two lowercase hex digits each.
    static func bytes(_ b: [UInt8]) -> String {
        "x" + b.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    static func headers(_ hs: [Header]) -> String {
        "headers=\(hs.count)" + hs.map { " \(str($0.name)) \(str($0.value))" }.joined()
    }

    static func request(_ r: Request) -> String {
        switch r {
        case let .readFile(p): return "readFile \(str(p))"
        case let .writeFile(p, d): return "writeFile \(str(p)) \(bytes(d))"
        case let .playSound(n): return "sound \(str(n))"
        case let .http(m, u, hs, b, t, sec, cap, red):
            let tail = "secret=\(opt(sec, secret)) capture=\(cap.count)" + cap.map { " \(str($0.field)) \(str($0.account))" }.joined()
            if red {
                let n = u.utf8.count + hs.reduce(0) { $0 + $1.name.utf8.count + $1.value.utf8.count } + b.count
                return "http \(str(m)) timeout=\(t) <redacted \(n) bytes> " + tail
            }
            return "http \(str(m)) \(str(u)) timeout=\(t) \(headers(hs)) body=\(bytes(b)) " + tail
        case let .appendFile(p, d): return "appendFile \(str(p)) \(bytes(d))"
        case let .listDir(p): return "listDir \(str(p))"
        case let .deleteFile(p): return "deleteFile \(str(p))"
        case .frontmostApp: return "frontmostApp"
        case let .permission(p, prompt): return "permission \(p.rawValue) \(bit(prompt))"
        case let .typeText(pid, t, ret): return "typeText \(pid) \(bit(ret)) \(str(t))"
        case let .upload(m, u, hs, sec, body, t):
            return "upload \(str(m)) \(str(u)) timeout=\(t) \(headers(hs)) secret=\(opt(sec, secret)) parts=\(body.count)"
                + body.map { " " + part($0) }.joined()
        case let .forgetClip(c): return "forgetClip \(c)"
        case let .openItem(t): return "open \(str(t))"
        case let .appRunning(b): return "appRunning \(str(b))"
        case let .readDefault(d, k): return "readDefault \(str(d)) \(str(k))"
        case let .makeDir(p): return "makeDir \(str(p))"
        case let .loadImage(src, r): return "loadImage \(bit(r)) \(str(src))"
        case let .forgetSecret(a): return "forgetSecret \(str(a))"
        }
    }

    static func secret(_ s: Secret) -> String {
        switch s.source {
        case let .env(f, n): "\(str(s.header)) \(str(s.scheme)) \(str(f)) \(str(n))"
        case let .keychain(a): "\(str(s.header)) \(str(s.scheme)) keychain \(str(a))"
        }
    }

    static func part(_ p: Part) -> String {
        switch p {
        case let .bytes(b): return "bytes \(bytes(b))"
        case let .wav(c, s, e): return "wav \(c) \(s) \(opt(e) { "\($0)" })"
        }
    }

    static func subEvent(_ e: SubEvent) -> String {
        switch e {
        case .tick: return "0"
        case .changed: return "1"
        case let .audio(n, pk, ws): return "2 \(n) \(pk) \(ws.count)" + ws.map { " \($0.sumSq):\($0.peak)" }.joined()
        case let .keyDown(t): return "3 \(t)"
        case let .keyUp(t): return "4 \(t)"
        case let .otherKey(t): return "5 \(t)"
        case let .failed(f, m): return "6 \(f.rawValue) \(str(m))"
        case let .started(t): return "7 \(t)"
        case let .evicted(s): return "8 \(str(s))"
        }
    }

    static func reply(_ r: Reply) -> String {
        switch r {
        case .done: return "done"
        case let .bytes(d): return "bytes \(bytes(d))"
        case let .http(st, hs, b): return "http \(st) \(headers(hs)) body=\(bytes(b))"
        case let .failed(f, m): return "failed \(f.rawValue) \(str(m))"
        case let .names(ns): return "names \(ns.count)" + ns.map { " " + str($0) }.joined()
        case let .app(pid, n): return "app \(pid) \(str(n))"
        case let .flag(b): return "flag \(bit(b))"
        case let .image(w, h): return "image \(w) \(h)"
        }
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
        case let .clock(t): return "clock \(t.mono) \(t.wall) \(t.zone)"
        case let .reply(id, r): return "reply \(id) \(reply(r))"
        case let .subEvent(id, e): return "sub \(id) \(subEvent(e))"
        case let .surface(p, e): return "surface \(p) " + event(e)
        case let .menuOpen(p): return "menuOpen \(p)"
        case let .menuClose(p): return "menuClose \(p)"
        case let .menuSelect(p, r): return "menuSelect \(p) \(ref(r))"
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
        return try event(&t, line)
    }

    static func event(_ t: inout Tokens, _ line: String) throws -> Event {
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
            } else if code == 14 { k = .menu
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
        case "clock":
            guard let m = UInt64(t.word()), let w = Int64(t.word()) else { throw Bad(line: line) }
            return .clock(Time(mono: m, wall: w, zone: try i()))
        case "reply":
            let id = try u()
            func hexBytes(_ w: String) throws -> [UInt8] {
                guard w.hasPrefix("x") else { throw Bad(line: line) }
                let h = Array(w.utf8.dropFirst())
                guard h.count % 2 == 0 else { throw Bad(line: line) }
                return try stride(from: 0, to: h.count, by: 2).map { i in
                    guard let b = UInt8(String(decoding: h[i..<i + 2], as: UTF8.self), radix: 16) else {
                        throw Bad(line: line)
                    }
                    return b
                }
            }
            switch t.word() {
            case "done": return .reply(id: id, .done)
            case "bytes": return .reply(id: id, .bytes(try hexBytes(t.word())))
            case "http":
                let st = try u()
                let hw = t.word()
                guard hw.hasPrefix("headers="), let n = Int(hw.dropFirst(8)) else { throw Bad(line: line) }
                var hs: [Header] = []
                for _ in 0..<n {
                    let k = try t.string()
                    hs.append(Header(k, try t.string()))
                }
                let bw = t.word()
                guard bw.hasPrefix("body=") else { throw Bad(line: line) }
                return .reply(id: id, .http(status: st, headers: hs, body: try hexBytes(String(bw.dropFirst(5)))))
            case "failed":
                guard let f = Fault(rawValue: try u8()) else { throw Bad(line: line) }
                return .reply(id: id, .failed(f, try t.string()))
            case "names":
                guard let n = Int(t.word()) else { throw Bad(line: line) }
                return .reply(id: id, .names(try (0..<n).map { _ in try t.string() }))
            case "app":
                let pid = try u()
                return .reply(id: id, .app(pid: pid, name: try t.string()))
            case "flag": return .reply(id: id, .flag(try u8() == 1))
            case "image":
                let w = try u()
                return .reply(id: id, .image(width: w, height: try u()))
            default: throw Bad(line: line)
            }
        case "surface":
            let p = try u()
            return .surface(place: p, try event(&t, line))
        case "menuOpen": return .menuOpen(place: try u())
        case "menuClose": return .menuClose(place: try u())
        case "menuSelect":
            let p = try u()
            let parts = t.word().split(separator: "#")
            guard parts.count == 2, let c = UInt32(parts[0]), let k = UInt32(parts[1]) else { throw Bad(line: line) }
            return .menuSelect(place: p, ControlRef(claim: c, key: k))
        case "sub":
            let id = try u()
            func u64() throws -> UInt64 { guard let v = UInt64(t.word()) else { throw Bad(line: line) }; return v }
            switch try u8() {
            case 0: return .subEvent(id: id, .tick)
            case 1: return .subEvent(id: id, .changed)
            case 2:
                let n = try u(), pk = try u(), c = try u()
                let ws = try (0..<c).map { _ -> Level in
                    let parts = t.word().split(separator: ":")
                    guard parts.count == 2, let s = UInt64(parts[0]), let p = UInt32(parts[1]) else { throw Bad(line: line) }
                    return Level(sumSq: s, peak: p)
                }
                return .subEvent(id: id, .audio(frames: n, peak: pk, windows: ws))
            case 3: return .subEvent(id: id, .keyDown(try u64()))
            case 4: return .subEvent(id: id, .keyUp(try u64()))
            case 5: return .subEvent(id: id, .otherKey(try u64()))
            case 6:
                guard let f = Fault(rawValue: try u8()) else { throw Bad(line: line) }
                return .subEvent(id: id, .failed(f, try t.string()))
            case 7: return .subEvent(id: id, .started(try u64()))
            case 8: return .subEvent(id: id, .evicted(try t.string()))
            default: throw Bad(line: line)
            }
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
