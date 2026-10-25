import AppKit
import CairnFrame
import Testing
@testable import CairnHost

@Suite struct KeyMappingTests {
    @Test func selectors() {
        #expect(KeyMapping.command("moveLeft:") == .key(.left, Mods()))
        #expect(KeyMapping.command("moveWordRightAndModifySelection:") == .key(.right, Mods(shift: true, option: true)))
        #expect(KeyMapping.command("deleteBackward:") == .key(.backspace, Mods()))
        #expect(KeyMapping.command("insertNewline:") == .key(.enter, Mods()))
        #expect(KeyMapping.command("cancelOperation:") == .key(.escape, Mods()))
        #expect(KeyMapping.command("selectAll:") == .selectAll)
        #expect(KeyMapping.command("noop:") == nil)
        #expect(KeyMapping.command("complete:") == nil)
    }

    @Test func rawKeys() {
        let cmd = Mods(command: true)
        #expect(KeyMapping.key(keyCode: 40, charactersIgnoringModifiers: "K", mods: cmd) == .key(.char("k"), cmd))
        #expect(KeyMapping.key(keyCode: 36, charactersIgnoringModifiers: "\r", mods: Mods()) == .key(.enter, Mods()))
        #expect(KeyMapping.key(keyCode: 122, charactersIgnoringModifiers: "\u{F704}", mods: Mods()) == nil)  // F1
        #expect(KeyMapping.key(keyCode: 0, charactersIgnoringModifiers: nil, mods: Mods()) == nil)
        // A synthesized event with several characters is one key per character, in order.
        #expect(KeyMapping.keys(keyCode: 0, charactersIgnoringModifiers: "Wa\u{F704}l", mods: Mods())
                == [.key(.char("w"), Mods()), .key(.char("a"), Mods()), .key(.char("l"), Mods())])
        #expect(KeyMapping.keys(keyCode: 36, charactersIgnoringModifiers: "\r\r", mods: Mods()) == [.key(.enter, Mods())])
    }

    @Test func modifiers() {
        #expect(KeyMapping.mods([.command, .shift]) == Mods(shift: true, command: true))
        #expect(KeyMapping.mods([.capsLock]) == Mods())
    }
}

@Suite struct ScrollTests {
    @Test func preciseCarriesRemainder() {
        var a = ScrollAccumulator()
        #expect(a.add(deltaX: 0, deltaY: -0.4, precise: true) == nil)
        let r = a.add(deltaX: 0, deltaY: -0.7, precise: true)
        #expect(r?.dy == 1)  // positive is toward the end
        #expect(r?.dx == 0)
    }

    @Test func linesScale() {
        var a = ScrollAccumulator()
        let r = a.add(deltaX: 1, deltaY: 2, precise: false)
        #expect(r?.dx == -16)
        #expect(r?.dy == -32)
    }

    @Test func sumTracksInput() {
        var a = ScrollAccumulator()
        var total = 0
        for _ in 0..<100 { total += Int(a.add(deltaX: 0, deltaY: -0.33, precise: true)?.dy ?? 0) }
        #expect(abs(Double(total) - 33) < 1)
    }
}

@Suite struct CoalesceTests {
    @Test func moves() {
        let p = Point(x: 3, y: 4)
        #expect(Engine.coalesce(.pointerMove(Point(x: 1, y: 1)), .pointerMove(p)) == .pointerMove(p))
    }

    @Test func scrolls() {
        let p = Point(x: 1, y: 1)
        #expect(Engine.coalesce(.scroll(p, dx: 1, dy: 2), .scroll(p, dx: 3, dy: -5)) == .scroll(p, dx: 4, dy: -3))
    }

    @Test func clicksNeverMerge() {
        let p = Point(x: 1, y: 1)
        #expect(Engine.coalesce(.pointerMove(p), .pointerDown(p, .primary, clicks: 1, Mods())) == nil)
        #expect(Engine.coalesce(.pointerDown(p, .primary, clicks: 1, Mods()), .pointerMove(p)) == nil)
    }
}

@MainActor @Suite struct AXKeyTests {
    let r = Rect(x: 0, y: 0, w: 10, h: 10)

    @Test func controlsKeyByRef() {
        let nodes = [AxNode(control: ControlRef(claim: 5, key: 12), role: .checkbox, rect: r, label: "a"),
                     AxNode(control: ControlRef(claim: 2), role: .button, rect: r, label: "b")]
        #expect(AXMirror.keys(nodes) == ["^5#12", "^2"])
    }

    @Test func anonymousKeyByParentAndOrdinal() {
        let nodes = [AxNode(control: nil, role: .list, rect: r, label: "L"),
                     AxNode(control: nil, role: .text, rect: r, label: "x", parent: 0),
                     AxNode(control: nil, role: .text, rect: r, label: "y", parent: 0)]
        let k = AXMirror.keys(nodes)
        #expect(Set(k).count == 3)
        #expect(k[1].hasPrefix(k[0]))
    }

    @Test func cyclesDetected() {
        let nodes = [AxNode(control: nil, role: .group, rect: r, label: "", parent: 1),
                     AxNode(control: nil, role: .group, rect: r, label: "", parent: 0)]
        #expect(AXMirror.cycles(nodes, from: 0))
        _ = AXMirror.keys(nodes)  // terminates
    }

    @Test func scrolledOutChildrenHidden() {
        let empty = Rect(x: 0, y: 0, w: 10, h: 0)
        let nodes = [AxNode(control: nil, role: .scrollArea, rect: r, label: ""),
                     AxNode(control: ControlRef(claim: 1, key: 1), role: .button, rect: r, label: "in", parent: 0),
                     AxNode(control: ControlRef(claim: 1, key: 2), role: .button, rect: empty, label: "out", parent: 0),
                     AxNode(control: nil, role: .text, rect: r, label: "under out", parent: 2),
                     AxNode(control: nil, role: .text, rect: empty, label: "not scrolled")]
        #expect(AXMirror.hidden(nodes) == [false, false, true, true, false])
    }
}
