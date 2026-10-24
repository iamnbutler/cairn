import AppKit
import CairnFrame

/// Runs one app: its window, if it has one, and its other surfaces (status items, panels; see
/// `SurfaceHost`). An app whose first frame has no window runs as an accessory: no Dock icon and
/// no main menu (docs/surfaces.md, decision 4). An executable describes its app and calls
/// `CairnApp.main`:
///
/// ```swift
/// CairnApp.main(CairnApp.Config(title: "Counter", size: Size(w: 480, h: 320)) { LeanCore(counter) })
/// ```
///
/// Flags every app gets:
/// - `--stats`: print latency percentiles to stderr every two seconds and at quit.
/// - `--latency N`: post N synthetic pointer moves and clicks through the real window and
///   AppKit event path, print input → frame and input → present, and quit.
@MainActor
public enum CairnApp {
    public struct Config {
        public var title: String
        public var size: Size
        public var makeCore: () -> AppCore
        public var makeRenderer: () -> FrameRenderer
        /// The world the app's effects and subscriptions reach, given whether the debug socket is
        /// on (driven detached): an app that records or types swaps in fakes then.
        public var makeWorld: (_ debug: Bool) -> World

        public init(title: String, size: Size, makeRenderer: @escaping () -> FrameRenderer = { MetalRenderer() },
                    makeWorld: @escaping (_ debug: Bool) -> World = { _ in World() },
                    makeCore: @escaping () -> AppCore) {
            self.title = title
            self.size = size
            self.makeCore = makeCore
            self.makeRenderer = makeRenderer
            self.makeWorld = makeWorld
        }
    }

    public static func main(_ config: Config) -> Never {
        let app = NSApplication.shared
        let delegate = Delegate(config: config)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }

    static func menu(title: String) -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: title)
        appMenu.addItem(withTitle: "Hide \(title)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(title)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApplication.shared.windowsMenu = window
        return main
    }

    final class Delegate: NSObject, NSApplicationDelegate {
        let config: Config
        var window: NSWindow?
        var view: HostView!
        var surfaces: SurfaceHost!
        var hasWindow = true
        var statsTimer: Timer?
        var debug: DebugServer?

        init(config: Config) { self.config = config }

        func applicationDidFinishLaunching(_ note: Notification) {
            let size = NSSize(width: CGFloat(config.size.w), height: CGFloat(config.size.h))
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            // Off unless CAIRN_DEBUG_SOCKET or --debug-socket asks for it (docs/conformance.md).
            debug = DebugServer.requested(title: config.title)
            let engine = Engine(size: config.size, scalePercent: HostView.percent(scale),
                                world: config.makeWorld(debug != nil), makeCore: config.makeCore)
            view = HostView(engine: engine, renderer: debug?.renderer ?? config.makeRenderer(), size: size)
            surfaces = SurfaceHost(engine: engine, mode: debug == nil ? .live : .detached) {
                MetalRenderer(clearColor: Color(r: 0, g: 0, b: 0, a: 0))
            }
            view.onApply = { [surfaces] frame in surfaces?.apply(frame) }
            engine.start()
            // Whether there is a window is the app's first frame's to say.
            let first = engine.wait(through: 0)
            hasWindow = first.map { $0.frame.windowIndex != nil } ?? true
            if hasWindow {
                NSApp.setActivationPolicy(.regular)
                NSApp.mainMenu = CairnApp.menu(title: config.title)
                let title = first?.frame.windowIndex.map { first!.frame.surfaces[$0].title } ?? ""
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                      backing: .buffered, defer: false)
                window.title = title.isEmpty ? config.title : title
                window.contentView = view
                window.makeFirstResponder(view)
                window.center()
                window.setFrameAutosaveName("cairn.\(config.title)")
                self.window = window
            } else {
                NSApp.setActivationPolicy(.accessory)  // no Dock icon, no main menu
            }
            view.applyLatestFrame()
            if let debug {
                // Driven only through the socket: shown without taking focus from the person at the
                // keyboard, and deaf to the real mouse.
                debug.attach(view: view, window: window, surfaces: surfaces)
            } else if let window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }

            let args = CommandLine.arguments
            if args.contains("--stats") {
                statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [engine] _ in
                    FileHandle.standardError.write((engine.stats.report + "\n").data(using: .utf8)!)
                }
            }
            if let i = args.firstIndex(of: "--latency") {
                let n = i + 1 < args.count ? Int(args[i + 1]) ?? 200 : 200
                LatencyProbe(view: view, count: n).start()
            }
        }

        func applicationWillTerminate(_ note: Notification) {
            if CommandLine.arguments.contains("--stats") {
                FileHandle.standardError.write((view.engine.stats.report + "\n").data(using: .utf8)!)
            }
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { hasWindow }
    }
}

/// Feeds synthetic mouse events to the view at a steady rate, through the host's input mapping
/// (not the HID system or AppKit's dispatch, which won't deliver clicks to an inactive window),
/// then prints the engine's latency stats. Moves alternate with clicks in the window's empty
/// bottom-left corner.
@MainActor
final class LatencyProbe {
    let view: HostView
    let count: Int
    var sent = 0

    init(view: HostView, count: Int) { self.view = view; self.count = count }

    func start() {
        // Let the first frame land and the display link settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            view.engine.stats.reset()
            tick()
        }
    }

    private func tick() {
        guard let window = view.window else { return }
        if sent >= count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                print("latency over \(count) synthetic events (\(view.engine.stats.summary(.inputToFrame).count) batches):")
                print(view.engine.stats.report)
                NSApp.terminate(nil)
            }
            return
        }
        let h = view.bounds.height
        let p = view.convert(NSPoint(x: 10 + CGFloat(sent % 50), y: h - 10), to: nil)
        let type: NSEvent.EventType = sent % 4 == 3 ? .leftMouseDown : (sent % 4 == 0 && sent > 0 ? .leftMouseUp : .mouseMoved)
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: sent, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        if let e {
            switch type {
            case .leftMouseDown: view.mouseDown(with: e)
            case .leftMouseUp: view.mouseUp(with: e)
            default: view.mouseMoved(with: e)
            }
        }
        sent += 1
        // ~ 3 events per 60 Hz frame on average, uncorrelated with the display link.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0047) { [self] in tick() }
    }
}
