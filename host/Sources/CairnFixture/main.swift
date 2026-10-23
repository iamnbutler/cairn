import AppKit
import CairnFrame
import CairnHost

// A stand-in app written in Swift, for checking the host by hand before a Lean app has a text
// field: IME and dead keys, the accessibility mirror (heading, text field, checkbox, button,
// list), cursor and clipboard effects. It implements `AppCore` like `LeanCore` does, so the
// host can't tell the difference. Not product code: the real versions of all of this are
// Lean's (workstreams C and D), and nothing here is proved.
//
//   CairnFixture [--stats]

final class FixtureCore: AppCore {
    let font = Font(family: 0, size: 15, weight: 400, italic: false)
    lazy var nsFont = NSFont.systemFont(ofSize: 15, weight: .regular)

    var size = Size(w: 520, h: 420)
    var text: [Unicode.Scalar] = []
    var anchor = 0, caret = 0
    var marked: Range<Int>?
    var focused = false
    var done = false
    var items: [(id: UInt32, text: String)] = []
    var nextId: UInt32 = 1
    var hover: ControlRef?
    var pressed: ControlRef?
    var pointer: Point?
    var effects: [Effect] = []

    let field = ControlRef(claim: 1), check = ControlRef(claim: 2), add = ControlRef(claim: 3)
    var fieldRect: Rect { Rect(x: 24, y: 64, w: max(120, size.w - 48 - 100), h: 34) }
    var addRect: Rect { Rect(x: fieldRect.x + fieldRect.w + 12, y: 64, w: 88, h: 34) }
    var checkRect: Rect { Rect(x: 24, y: 112, w: 22, h: 22) }
    func itemRect(_ i: Int) -> Rect { Rect(x: 24, y: Int32(152 + 34 * i), w: size.w - 48, h: 30) }

    func start(size: Size, scalePercent: UInt32) { self.size = size }

    // MARK: Text model

    var string: String { var u = String.UnicodeScalarView(); u.append(contentsOf: text); return String(u) }
    var sel: Range<Int> { min(anchor, caret)..<max(anchor, caret) }

    func replace(_ r: Range<Int>, _ s: String) -> Int {
        let lo = min(r.lowerBound, text.count), hi = min(max(r.upperBound, lo), text.count)
        text.replaceSubrange(lo..<hi, with: s.unicodeScalars)
        return lo
    }
    func range(_ r: ScalarRange?) -> Range<Int>? { r.map { Int($0.start)..<Int(max($0.start, $0.end)) } }

    func edit(_ e: Event) {
        switch e {
        case let .insertText(s, r):
            let lo = replace(range(r) ?? marked ?? sel, s)
            marked = nil
            anchor = lo + s.unicodeScalars.count; caret = anchor
        case let .setMarked(s, a, n, r):
            let lo = replace(range(r) ?? marked ?? sel, s)
            let len = s.unicodeScalars.count
            marked = len == 0 ? nil : lo..<(lo + len)
            anchor = lo + min(Int(a), len); caret = lo + min(Int(a + n), len)
        case .unmark:
            marked = nil
        case let .key(k, m):
            let n = text.count
            func move(_ to: Int) { caret = max(0, min(n, to)); if !m.shift { anchor = caret } }
            switch k {
            case .left: if !m.shift && !sel.isEmpty { move(sel.lowerBound) } else { move(m.command ? 0 : caret - 1) }
            case .right: if !m.shift && !sel.isEmpty { move(sel.upperBound) } else { move(m.command ? n : caret + 1) }
            case .home, .up: move(0)
            case .finish, .down: move(n)
            case .backspace:
                if !sel.isEmpty { caret = replace(sel, ""); anchor = caret }
                else if caret > 0 { caret = replace((caret - 1)..<caret, ""); anchor = caret }
                else { effects.append(.beep) }
            case .delete:
                if !sel.isEmpty { caret = replace(sel, ""); anchor = caret }
                else if caret < n { _ = replace(caret..<(caret + 1), "") }
            case .enter: submit()
            case .escape: focused = false
            default: break
            }
        case .selectAll: anchor = 0; caret = text.count
        case .copy: if !sel.isEmpty { effects.append(.setClipboard(String(String.UnicodeScalarView(text[sel])))) }
        case .cut:
            if !sel.isEmpty {
                effects.append(.setClipboard(String(String.UnicodeScalarView(text[sel]))))
                caret = replace(sel, ""); anchor = caret
            }
        case .paste(let s): let lo = replace(sel, s); anchor = lo + s.unicodeScalars.count; caret = anchor
        default: break
        }
    }

    func submit() {
        let s = string.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { effects.append(.beep); return }
        items.append((nextId, s)); nextId += 1
        text = []; anchor = 0; caret = 0; marked = nil
    }

    // MARK: Interaction

    func hit(_ p: Point) -> ControlRef? {
        func inside(_ r: Rect) -> Bool { p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h }
        if inside(fieldRect) { return field }
        if inside(addRect) { return add }
        if inside(checkRect) { return check }
        for (i, it) in items.enumerated() where inside(itemRect(i)) { return ControlRef(claim: 4, key: it.id) }
        return nil
    }

    func step(_ events: [Event]) {
        effects = []
        for e in events {
            switch e {
            case .pointerMove(let p): pointer = p; hover = hit(p)
            case .pointerExit: pointer = nil; hover = nil
            case let .pointerDown(p, .primary, _, _):
                pressed = hit(p)
                if pressed == field {
                    focused = true
                    marked = nil
                    let i = index(atX: CGFloat(p.x - fieldRect.x - 10))
                    caret = i; anchor = i
                } else if pressed != nil { focused = false }
            case let .pointerUp(p, .primary, _):
                if let c = pressed, c == hit(p) {
                    if c == check { done.toggle() }
                    if c == add { submit() }
                    if c.claim == 4 { items.removeAll { $0.id == c.key } }
                }
                pressed = nil
            case .resize(let s): size = s
            case .windowFocus, .scale, .scroll, .pointerDown, .pointerUp: break
            default: if focused { edit(e) }
            }
        }
    }

    func line(_ s: String) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: nsFont]))
    }
    func x(_ i: Int) -> Int32 {
        let u = TextIndex(string).utf16(i)
        return Int32(CTLineGetOffsetForStringIndex(line(string), u, nil).rounded())
    }
    func index(atX x: CGFloat) -> Int {
        let u = CTLineGetStringIndexForPosition(line(string), CGPoint(x: x, y: 0))
        return TextIndex(string).scalar(max(0, u))
    }

    // MARK: Frame

    func frame() throws -> Frame {
        let ink = Color(r: 30, g: 30, b: 34, a: 255), white = Color(r: 255, g: 255, b: 255, a: 255)
        let blue = Color(r: 40, g: 100, b: 230, a: 255)
        var draws: [Draw] = [.text(origin: Point(x: 24, y: 44), font: Font(family: 0, size: 22, weight: 700, italic: false), color: ink, string: "Host fixture")]
        var ax: [AxNode] = [AxNode(control: nil, role: .heading, rect: Rect(x: 24, y: 20, w: 200, h: 30), label: "Host fixture")]

        let f = fieldRect
        draws.append(.rect(f, fill: white, radius: 6, border: Border(width: focused ? 2 : 1, color: focused ? blue : Color(r: 180, g: 180, b: 186, a: 255))))
        let ox = f.x + 10, base = f.y + 22
        draws.append(.pushClip(f))
        if focused && !sel.isEmpty {
            draws.append(.rect(Rect(x: ox + x(sel.lowerBound), y: f.y + 7, w: x(sel.upperBound) - x(sel.lowerBound), h: 20),
                               fill: Color(r: 180, g: 210, b: 255, a: 255), radius: 0, border: nil))
        }
        draws.append(.text(origin: Point(x: ox, y: base), font: font, color: ink, string: string))
        if let m = marked {
            draws.append(.rect(Rect(x: ox + x(m.lowerBound), y: base + 3, w: x(m.upperBound) - x(m.lowerBound), h: 2), fill: ink, radius: 0, border: nil))
        }
        let caretRect = Rect(x: ox + x(caret), y: f.y + 7, w: 1, h: 20)
        if focused && sel.isEmpty { draws.append(.rect(caretRect, fill: ink, radius: 0, border: nil)) }
        draws.append(.popClip)
        ax.append(AxNode(control: field, role: .textField, rect: f, label: "New item", value: string, focused: focused))

        let a = addRect
        draws.append(.rect(a, fill: hover == add ? Color(r: 30, g: 80, b: 200, a: 255) : blue, radius: 6, border: nil))
        draws.append(.text(origin: Point(x: a.x + 28, y: a.y + 22), font: Font(family: 0, size: 14, weight: 600, italic: false), color: white, string: "Add"))
        ax.append(AxNode(control: add, role: .button, rect: a, label: "Add"))

        let c = checkRect
        draws.append(.rect(c, fill: done ? blue : white, radius: 4, border: Border(width: 1, color: Color(r: 150, g: 150, b: 160, a: 255))))
        draws.append(.text(origin: Point(x: c.x + 32, y: c.y + 16), font: font, color: ink, string: "Done"))
        ax.append(AxNode(control: check, role: .checkbox, rect: c, label: "Done", checked: done))

        let listIndex = ax.count
        ax.append(AxNode(control: nil, role: .list, rect: Rect(x: 24, y: 152, w: size.w - 48, h: Int32(34 * max(1, items.count))), label: "Items"))
        for (i, it) in items.enumerated() {
            let r = itemRect(i), ref = ControlRef(claim: 4, key: it.id)
            draws.append(.rect(r, fill: hover == ref ? Color(r: 238, g: 238, b: 242, a: 255) : nil, radius: 4, border: nil))
            draws.append(.text(origin: Point(x: r.x + 8, y: r.y + 20), font: font, color: ink, string: it.text))
            ax.append(AxNode(control: ref, role: .listItem, rect: r, label: it.text, parent: listIndex))
        }

        let cursor: Cursor = hover == field ? .text : (hover != nil ? .pointer : .arrow)
        let input = focused ? TextInput(control: field, rect: f, caret: caretRect, text: string,
                                        selection: (UInt32(anchor), UInt32(caret)),
                                        marked: marked.map { (UInt32($0.lowerBound), UInt32($0.upperBound)) }) : nil
        return Frame(size: size, draws: draws, ax: ax, textInput: input, cursor: cursor, effects: effects)
    }
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Host Fixture", size: Size(w: 520, h: 420)) { FixtureCore() })
}
