import AppKit
import CairnFrame
import CairnRender
import Darwin

/// The debug socket (docs/conformance.md): a Unix socket through which a tool drives one running
/// app and reads back what it shows. Off unless asked for:
///
///     CAIRN_DEBUG_SOCKET=1 CairnBasics            # $TMPDIR/cairn-<title>-<pid>.sock
///     CAIRN_DEBUG_SOCKET=/path/x.sock CairnBasics
///     CairnBasics --debug-socket [/path/x.sock]
///
/// Requests and replies are one JSON object per line. Input goes into this app's own view as
/// NSEvents passed to its responder methods (`mouseDown(with:)`, `keyDown(with:)`, …), or through
/// the `NSTextInputClient` and Edit-menu entry points AppKit itself calls, so it crosses the real
/// host path. Nothing is posted to the window server: no other app can receive it, and this one
/// needn't be frontmost. Under the socket the window is shown without activating the app and
/// ignores the real mouse, effects are recorded (clipboard writes go to a private pasteboard,
/// beeps are silenced), and the renderer keeps a copy of each presented drawable for `pixels`.
///
/// | Request | Reply |
/// |---|---|
/// | `{"cmd":"hello"}` | title, pid, window number, logical size, scale × 100, clear colour, last seq |
/// | `{"cmd":"pointer","type":"move"\|"down"\|"up"\|"exit","at":[x,y],"clicks":1}` | `seq` |
/// | `{"cmd":"key","key":"enter","mods":["shift"],"char":" "}` | `seq` |
/// | `{"cmd":"text","op":"insert"\|"marked"\|"unmark","text":"…","sel":[start,len]}` | `seq` |
/// | `{"cmd":"menu","name":"copy"\|"cut"\|"paste"\|"selectAll"\|"undo"\|"redo"}` | `seq` |
/// | `{"cmd":"menu","place":450}` (no `name`) | a status item's native menu as AppKit holds it: each item's title, enabled, state, id, key equivalent, submenu |
/// | `{"cmd":"menuOpen","place":450}`, `{"cmd":"menuClose",…}` | `seq`: the menu's delegate was told it opened (closed) |
/// | `{"cmd":"menuSelect","place":450,"id":"^457#0"}` | `seq`: the item was chosen through `NSMenu.performActionForItem(at:)`; a disabled item's action is sent directly (`"direct":true`), as when the menu changed while open |
/// | `{"cmd":"menuSelect","place":450,"ref":[456,0]}` | `seq`: a `menuSelect` event with any ref, in or out of the menu |
/// | `{"cmd":"surfaces"}` | the activation policy, key window and main menu; each surface's record and its AppKit object (status item, panel: level, key, mouse, Spaces, frame) |
/// | `{"cmd":"wait","seq":N,"timeout":5}` | the frame's `seq` and `version`, effects run since the last wait, new text-shadow divergences |
/// | `{"cmd":"frame"}` | the last applied frame, decoded, with its `seq` and `version` |
/// | `{"cmd":"ax"}` | the accessibility tree, as `NSAccessibility` answers it |
/// | `{"cmd":"pixels","points":[[x,y],…]}` | colours from the presented drawable (`source: "drawable"`), else from an offscreen render of the frame (`"offscreen"`) |
/// | `{"cmd":"restart"}` | `seq`: the app starts again from its initial state |
/// | `{"cmd":"snapshot","path":"…"}` | writes the presented drawable as PNG |
/// | `{"cmd":"quit"}` | |
public final class DebugServer: @unchecked Sendable {
    public let path: String
    let renderer = DebugRenderer()
    private weak var view: HostView?
    private weak var surfaces: SurfaceHost?
    private var engine: Engine?
    private let lock = NSLock()
    private var effects: [Effect] = []
    private var seenDivergences = 0
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("cairn.debug.\(getpid())"))
    private var offscreen: Renderer?  // the socket thread's own, for the fallback
    private var eventNumber = 0
    private var buttonDown = false
    private var title = ""

    init(path: String) { self.path = path }

    /// The server the command line or environment asks for, if any.
    public static func requested(title: String) -> DebugServer? {
        let args = CommandLine.arguments
        var path: String?
        if let i = args.firstIndex(of: "--debug-socket") {
            path = i + 1 < args.count && !args[i + 1].hasPrefix("--") ? args[i + 1] : ""
        } else if let env = ProcessInfo.processInfo.environment["CAIRN_DEBUG_SOCKET"], !env.isEmpty, env != "0" {
            path = env == "1" ? "" : env
        }
        guard var p = path else { return nil }
        if p.isEmpty { p = NSTemporaryDirectory() + "cairn-\(title)-\(getpid()).sock" }
        let s = DebugServer(path: p)
        s.title = title
        return s
    }

    @MainActor
    func attach(view: HostView, window: NSWindow?, surfaces: SurfaceHost? = nil) {
        self.view = view
        self.surfaces = surfaces
        engine = view.engine
        pasteboard.clearContents()
        view.pasteboard = pasteboard
        view.effectHook = { [self] e in
            lock.lock()
            effects.append(e)
            lock.unlock()
            if case .beep = e { return true }  // recorded, not sounded
            return false  // setClipboard runs, into the private pasteboard
        }
        NSApp.setActivationPolicy(.accessory)  // no Dock icon, no menu bar takeover
        window?.ignoresMouseEvents = true      // the real mouse passes through to what's below
        window?.orderFrontRegardless()         // on screen (so it renders), not key, not active
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [path, name = pasteboard.name] _ in
            unlink(path)
            NSPasteboard(name: name).releaseGlobally()
        }
        let t = Thread { [self] in serve() }
        t.name = "cairn.debug"
        t.start()
    }

    // MARK: Socket

    private func log(_ s: String) { FileHandle.standardError.write("cairn debug: \(s)\n".data(using: .utf8)!) }

    private func serve() {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard fd >= 0, bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            log("cannot open a socket at \(path)")
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        let old = umask(0o077)  // only this user may connect
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard bound == 0, listen(fd, 4) == 0 else {
            log("cannot listen at \(path): \(String(cString: strerror(errno)))")
            return
        }
        log("listening at \(path)")
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { continue }
            session(c)
            close(c)
        }
    }

    private func session(_ c: Int32) {
        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(c, &buf, buf.count)
            if n <= 0 { return }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: 10) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                var reply: [String: Any]
                do {
                    guard let req = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        throw DebugError("a request is a JSON object")
                    }
                    reply = try handle(req)
                    reply["ok"] = true
                } catch {
                    reply = ["ok": false, "error": "\(error)"]
                }
                var out = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"ok\":false}".utf8)
                out.append(10)
                if !writeAll(c, out) { return }
            }
        }
    }

    private func writeAll(_ c: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(c, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    // MARK: Commands

    struct DebugError: Error, CustomStringConvertible {
        let description: String
        init(_ s: String) { description = s }
    }

    private func onMain<T: Sendable>(_ body: @MainActor () throws -> T) throws -> T {
        try DispatchQueue.main.sync { try MainActor.assumeIsolated(body) }
    }

    @MainActor
    private func menuHost(_ place: UInt32?) throws -> MenuHost {
        guard let m = surfaces?.menu(place) else {
            throw DebugError(place.map { "no status item at ^\($0)" } ?? "no status item")
        }
        return m
    }

    private func liveView() throws -> HostView {
        guard let v = view else { throw DebugError("no view") }
        return v
    }

    private static func point(_ v: Any?) throws -> Point {
        guard let a = v as? [NSNumber], a.count == 2 else { throw DebugError("a point is [x, y]") }
        return Point(x: a[0].int32Value, y: a[1].int32Value)
    }

    private func handle(_ req: [String: Any]) throws -> [String: Any] {
        guard let engine else { throw DebugError("not attached") }
        let cmd = req["cmd"] as? String ?? ""
        switch cmd {
        case "hello":
            let (w, h, scale, number) = try onMain { () throws -> (Int, Int, Int, Int) in
                let v = try liveView()
                return (Int(v.logicalSize.w), Int(v.logicalSize.h),
                        Int(HostView.percent(v.window?.backingScaleFactor ?? 2)), v.window?.windowNumber ?? 0)
            }
            let c = renderer.clearColor
            return ["title": title, "pid": Int(getpid()), "window": number, "size": [w, h], "scale": scale,
                    "clear": [Int(c.r), Int(c.g), Int(c.b), Int(c.a)], "seq": Int(engine.lastSeq), "protocol": 1]

        case "pointer":
            let type = req["type"] as? String ?? ""
            let p = type == "exit" ? Point(x: 0, y: 0) : try Self.point(req["at"])
            let clicks = (req["clicks"] as? NSNumber)?.intValue ?? 1
            try onMain { try pointer(type, p, clicks: clicks) }
            return ["seq": Int(engine.lastSeq)]

        case "key":
            let key = req["key"] as? String ?? ""
            let mods = req["mods"] as? [String] ?? []
            let ch = req["char"] as? String
            try onMain { try self.key(key, mods: mods, char: ch) }
            return ["seq": Int(engine.lastSeq)]

        case "text":
            let op = req["op"] as? String ?? ""
            let text = req["text"] as? String ?? ""
            let sel = (req["sel"] as? [NSNumber])?.map(\.intValue) ?? [text.utf16.count, 0]
            try onMain {
                let v = try liveView()
                let none = NSRange(location: NSNotFound, length: 0)
                switch op {
                case "insert": v.insertText(text, replacementRange: none)
                case "marked":
                    // `sel` is in scalars (the model's unit); AppKit's selectedRange is UTF-16.
                    let ix = TextIndex(text)
                    let a = ix.utf16(min(sel[0], ix.scalarCount)), b = ix.utf16(min(sel[0] + sel[1], ix.scalarCount))
                    v.setMarkedText(text, selectedRange: NSRange(location: a, length: b - a), replacementRange: none)
                case "unmark": v.unmarkText()
                default: throw DebugError("unknown text op \(op)")
                }
            }
            return ["seq": Int(engine.lastSeq)]

        case "menu" where req["name"] == nil:
            let place = (req["place"] as? NSNumber)?.uint32Value
            let data = try onMain { () throws -> Data in
                let m = try menuHost(place)
                return try JSONSerialization.data(withJSONObject: ["place": Int(m.place), "items": DebugJSON.menu(m.root)])
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        case "menuOpen", "menuClose":
            let place = (req["place"] as? NSNumber)?.uint32Value
            try onMain {
                let m = try menuHost(place)
                if cmd == "menuOpen" { m.menuWillOpen(m.root) } else { m.menuDidClose(m.root) }
            }
            return ["seq": Int(engine.lastSeq)]

        case "menuSelect":
            let place = (req["place"] as? NSNumber)?.uint32Value
            if let raw = req["ref"] as? [NSNumber], raw.count == 2 {
                let ref = ControlRef(claim: raw[0].uint32Value, key: raw[1].uint32Value)
                let p = try onMain { try menuHost(place).place }
                return ["seq": Int(engine.send([.menuSelect(place: p, ref)]))]
            }
            guard let id = req["id"] as? String else { throw DebugError("menuSelect needs id or ref") }
            let direct = try onMain { () throws -> Bool in
                let m = try menuHost(place)
                guard let (menu, i) = m.find(id), let item = menu.item(at: i), item.action != nil
                else { throw DebugError("no actionable item \(id) in the menu") }
                if item.isEnabled {
                    menu.performActionForItem(at: i)
                    return false
                }
                m.choose(item)
                return true
            }
            return ["seq": Int(engine.lastSeq), "direct": direct]

        case "surfaces":
            let data = try onMain { () throws -> Data in
                try JSONSerialization.data(withJSONObject: DebugJSON.surfaces(surfaces, view: try liveView()))
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        case "menu":
            let name = req["name"] as? String ?? ""
            let selectors: [String: Selector] = [
                "copy": #selector(NSText.copy(_:)), "cut": #selector(NSText.cut(_:)),
                "paste": #selector(NSText.paste(_:)), "selectAll": #selector(NSResponder.selectAll(_:)),
                "undo": Selector(("undo:")), "redo": Selector(("redo:")),
            ]
            guard let sel = selectors[name] else { throw DebugError("unknown menu command \(name)") }
            // Sent to the view as the Edit menu's item would send it to the first responder.
            let handled = try onMain { NSApp.sendAction(sel, to: try liveView(), from: nil) }
            if !handled { throw DebugError("the view did not take \(name)") }
            return ["seq": Int(engine.lastSeq)]

        case "wait":
            let seq = (req["seq"] as? NSNumber).map { UInt64($0.intValue) } ?? engine.lastSeq
            let timeout = (req["timeout"] as? NSNumber)?.doubleValue ?? 5
            let deadline = Date(timeIntervalSinceNow: timeout)
            guard let p = engine.wait(through: seq, timeout: timeout) else { throw DebugError("no frame through #\(seq)") }
            // And the main thread has applied it: effects run, text input and the AX mirror updated.
            while try onMain({ try liveView().shown?.throughSeq ?? 0 }) < seq {
                if Date() > deadline { throw DebugError("frame #\(p.version) not applied on the main thread") }
                usleep(500)
            }
            let divergences = try onMain { () throws -> [String] in
                let all = try liveView().shadowDivergences
                let fresh = all.count >= seenDivergences ? all.suffix(all.count - seenDivergences) : all[...]
                seenDivergences = all.count
                return fresh.map { "\($0)" }
            }
            lock.lock()
            let ran = effects
            effects = []
            lock.unlock()
            return ["seq": Int(p.throughSeq), "version": p.version, "effects": ran.map(DebugJSON.effect),
                    "divergences": divergences]

        case "frame":
            let (frame, seq, version) = try onMain { () throws -> (Frame?, UInt64, Int) in
                let s = try liveView().shown
                return (s?.frame, s?.throughSeq ?? 0, s?.version ?? 0)
            }
            guard let frame else { throw DebugError("no frame yet") }
            return ["seq": Int(seq), "version": version, "frame": DebugJSON.frame(frame)]

        case "ax":
            let data = try onMain { () throws -> Data in
                try JSONSerialization.data(withJSONObject: DebugJSON.axTree(try liveView()))
            }
            return ["nodes": try JSONSerialization.jsonObject(with: data)]

        case "pixels":
            guard let raw = req["points"] as? [Any] else { throw DebugError("pixels needs points") }
            let points = try raw.map { try Self.point($0) }
            let timeout = (req["timeout"] as? NSNumber)?.doubleValue ?? 2
            guard let frame = engine.latest?.frame else { throw DebugError("no frame yet") }
            let deadline = Date(timeIntervalSinceNow: timeout)
            var colors = renderer.pixels(points, of: frame)
            while colors == nil && Date() < deadline {
                usleep(1000)
                colors = renderer.pixels(points, of: frame)
            }
            var source = "drawable"
            if colors == nil {
                // The window isn't being drawn (occluded, minimised): render the frame instead.
                source = "offscreen"
                if offscreen == nil { offscreen = try Renderer(); offscreen?.clearColor = renderer.clearColor }
                let scale = try onMain { try liveView().window?.backingScaleFactor ?? 2 }
                colors = try offscreen!.probe(frame, at: points, scale: Float(scale))
            }
            return ["source": source, "colors": (colors ?? []).map(DebugJSON.color)]

        case "restart":
            let (size, scale) = try onMain { () throws -> (Size, UInt32) in
                let v = try liveView()
                v.pasteboard.clearContents()
                return (v.logicalSize, HostView.percent(v.window?.backingScaleFactor ?? 2))
            }
            return ["seq": Int(engine.restart(size: size, scalePercent: scale))]

        case "snapshot":
            guard let path = req["path"] as? String else { throw DebugError("snapshot needs a path") }
            if !renderer.writePNG(to: URL(fileURLWithPath: path)) { throw DebugError("nothing rendered yet") }
            return ["path": path]

        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return [:]

        default:
            throw DebugError("unknown command \(cmd)")
        }
    }

    // MARK: Input, as AppKit would deliver it to the view

    @MainActor
    private func mouse(_ type: NSEvent.EventType, _ p: Point, clicks: Int) throws -> NSEvent {
        let v = try liveView()
        guard let w = v.window else { throw DebugError("no window") }
        // The point's centre, so the host's rounding down gives back exactly (x, y).
        let loc = v.convert(NSPoint(x: CGFloat(p.x) + 0.5, y: CGFloat(p.y) + 0.5), to: nil)
        eventNumber += 1
        guard let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                         context: nil, eventNumber: eventNumber, clickCount: clicks,
                                         pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0)
        else { throw DebugError("could not make a mouse event") }
        return e
    }

    @MainActor
    private func pointer(_ type: String, _ p: Point, clicks: Int) throws {
        let v = try liveView()
        switch type {
        case "move":
            // With the button held AppKit sends mouseDragged, not mouseMoved.
            if buttonDown { v.mouseDragged(with: try mouse(.leftMouseDragged, p, clicks: 1)) }
            else { v.mouseMoved(with: try mouse(.mouseMoved, p, clicks: 0)) }
        case "down":
            buttonDown = true
            v.mouseDown(with: try mouse(.leftMouseDown, p, clicks: clicks))
        case "up":
            buttonDown = false
            v.mouseUp(with: try mouse(.leftMouseUp, p, clicks: clicks))
        case "exit":
            guard let w = v.window,
                  let e = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
            else { throw DebugError("could not make an exit event") }
            v.mouseExited(with: e)
        default:
            throw DebugError("unknown pointer type \(type)")
        }
    }

    /// Key code, characters, and whether it's a function key, for each key the driver names.
    private static let keys: [String: (UInt16, String, Bool)] = [
        "enter": (36, "\r", false), "escape": (53, "\u{1b}", false), "tab": (48, "\t", false),
        "backspace": (51, "\u{7f}", false), "delete": (117, "\u{f728}", true),
        "left": (123, "\u{f702}", true), "right": (124, "\u{f703}", true),
        "up": (126, "\u{f700}", true), "down": (125, "\u{f701}", true),
        "home": (115, "\u{f729}", true), "end": (119, "\u{f72b}", true),
        "pageUp": (116, "\u{f72c}", true), "pageDown": (121, "\u{f72d}", true),
    ]

    @MainActor
    private func key(_ name: String, mods: [String], char: String?) throws {
        let v = try liveView()
        guard let w = v.window else { throw DebugError("no window") }
        var flags: NSEvent.ModifierFlags = []
        if mods.contains("shift") { flags.insert(.shift) }
        if mods.contains("command") { flags.insert(.command) }
        if mods.contains("option") { flags.insert(.option) }
        if mods.contains("control") { flags.insert(.control) }
        let code: UInt16, chars: String, plain: String
        if name == "char" {
            guard let c = char, !c.isEmpty else { throw DebugError("a char key needs char") }
            code = c == " " ? 49 : 0
            plain = c
            chars = c
        } else {
            guard let k = Self.keys[name] else { throw DebugError("unknown key \(name)") }
            code = k.0
            chars = name == "tab" && flags.contains(.shift) ? "\u{19}" : k.1  // Shift-Tab is backtab
            plain = chars
            if k.2 { flags.formUnion([.function, .numericPad]) }
        }
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                       context: nil, characters: chars, charactersIgnoringModifiers: plain,
                                       isARepeat: false, keyCode: code)
        else { throw DebugError("could not make a key event") }
        v.keyDown(with: e)
    }
}
