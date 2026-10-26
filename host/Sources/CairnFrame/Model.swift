// The Swift mirror of lean/Cairn/Frame.lean and lean/Cairn/Input.lean. The decoder and event
// encoder (Decode.swift, Encode.swift) are generated against docs/frame.md; these types are
// the contract the renderer and host code against. Initializers are public so other modules
// (host, renderer, tests) can build values.

public struct Point: Equatable, Sendable {
    public var x, y: Int32
    public init(x: Int32, y: Int32) { self.x = x; self.y = y }
}
public struct Size: Equatable, Sendable {
    public var w, h: Int32
    public init(w: Int32, h: Int32) { self.w = w; self.h = h }
}
public struct Rect: Equatable, Sendable {
    public var x, y, w, h: Int32
    public init(x: Int32, y: Int32, w: Int32, h: Int32) { self.x = x; self.y = y; self.w = w; self.h = h }
}
public struct Color: Hashable, Sendable {
    public var r, g, b, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
}
public struct Border: Hashable, Sendable {
    public var width: UInt32; public var color: Color
    public init(width: UInt32, color: Color) { self.width = width; self.color = color }
}

/// A font's width axis (SwiftUI's `Font.Width` presets); raw values are the wire codes.
public enum FontWidth: UInt8, Hashable, Sendable {
    case standard = 0, condensed = 1, expanded = 2, compressed = 3
}

public struct Font: Hashable, Sendable {
    public var family: UInt32  // 0 system UI, 1 system monospaced
    public var size: UInt32    // points
    public var weight: UInt32  // 100–900
    public var italic: Bool
    public var width: FontWidth
    /// Extra space after each character, in hundredths of a point.
    public var tracking: Int32
    /// Digits all one width.
    public var tabular: Bool
    public init(family: UInt32 = 0, size: UInt32 = 13, weight: UInt32 = 400, italic: Bool = false,
                width: FontWidth = .standard, tracking: Int32 = 0, tabular: Bool = false) {
        self.family = family; self.size = size; self.weight = weight; self.italic = italic
        self.width = width; self.tracking = tracking; self.tabular = tabular
    }

    /// The metrics ABI's style byte: bit 0 italic, bit 1 tabular, bits 2–3 the width.
    public var style: UInt8 { (italic ? 1 : 0) | (tabular ? 2 : 0) | (width.rawValue << 2) }

    public init(family: UInt32, size: UInt32, weight: UInt32, style: UInt8, tracking: Int32) {
        self.init(family: family, size: size, weight: weight, italic: style & 1 != 0,
                  width: FontWidth(rawValue: (style >> 2) & 3) ?? .standard, tracking: tracking,
                  tabular: style & 2 != 0)
    }
}

/// How a rounded rect's corners turn.
public enum Corner: UInt8, Hashable, Sendable {
    case circular = 0, continuous = 1
}

/// A soft shadow under a shape: its silhouette in `color`, blurred by `radius` points, moved by
/// `(x, y)`.
public struct Shadow: Hashable, Sendable {
    public var color: Color
    public var radius: UInt32
    public var x: Int32, y: Int32
    public init(color: Color, radius: UInt32, x: Int32 = 0, y: Int32 = 0) {
        self.color = color; self.radius = radius; self.x = x; self.y = y
    }
}

/// Host-drawn pixels: the registered shader `shader` fills the rect, fed with these numbers and
/// with the host's clock as milliseconds since `origin` (monotonic ms).
public struct Paint: Hashable, Sendable {
    public var shader: String
    public var origin: UInt64
    public var scalars: [Int32]
    public var arrays: [[Int32]]
    public init(shader: String, origin: UInt64 = 0, scalars: [Int32] = [], arrays: [[Int32]] = []) {
        self.shader = shader; self.origin = origin; self.scalars = scalars; self.arrays = arrays
    }
}

public enum Draw: Equatable, Sendable {
    case rect(Rect, fill: Color?, radius: UInt32, border: Border?)
    case text(origin: Point, font: Font, color: Color, string: String)  // origin: baseline left
    case pushClip(Rect)
    case popClip
    case paint(Rect, Paint)
    case shape(Rect, fill: Color?, radius: UInt32, border: Border?, corner: Corner, shadow: Shadow?)
    /// The image loaded from `source`, scaled into `dest` and clipped to the box `rect` (and any
    /// enclosing clip). Nothing is drawn while the host holds no image for `source`.
    case image(Rect, dest: Rect, source: String)
}

public enum Role: UInt8, Sendable {
    case group, button, checkbox, text, textField, link, list, listItem, heading, tab, scrollArea
}

public struct ControlRef: Hashable, Sendable {
    public var claim: UInt32
    public var key: UInt32
    public init(claim: UInt32, key: UInt32 = 0) { self.claim = claim; self.key = key }
    /// `^5`, or `^5#12` for one instance of a repeated control.
    public var label: String { key == 0 ? "^\(claim)" : "^\(claim)#\(key)" }
}

public struct AxNode: Equatable, Sendable {
    public var control: ControlRef?
    public var role: Role
    public var rect: Rect
    public var label: String
    public var value: String
    public var parent: Int?
    public var focused: Bool
    public var selected: Bool
    public var checked: Bool?
    /// A secure field: an `AXSecureTextField` with no value.
    public var secure: Bool
    /// The control has a menu (`AXShowMenu`); `true` when it is a menu button (`AXMenuButton`).
    public var menu: Bool?
    public init(control: ControlRef?, role: Role, rect: Rect, label: String, value: String = "",
                parent: Int? = nil, focused: Bool = false, selected: Bool = false, checked: Bool? = nil,
                secure: Bool = false, menu: Bool? = nil) {
        self.control = control; self.role = role; self.rect = rect; self.label = label; self.value = value
        self.parent = parent; self.focused = focused; self.selected = selected; self.checked = checked
        self.secure = secure; self.menu = menu
    }
}

public struct TextInput: Equatable, Sendable {
    public var control: ControlRef
    public var rect: Rect
    public var caret: Rect
    public var text: String
    public var selection: (start: UInt32, end: UInt32)
    public var marked: (start: UInt32, end: UInt32)?
    /// The left end of the text's baseline in window coordinates, after any horizontal scroll:
    /// where scalar 0 starts.
    public var textOrigin: Point
    /// A secure field: `text` is bullets, and the host turns on secure event input while it has
    /// focus (`SecureInput`).
    public var secure: Bool
    public init(control: ControlRef, rect: Rect, caret: Rect, text: String,
                selection: (start: UInt32, end: UInt32), marked: (start: UInt32, end: UInt32)?,
                textOrigin: Point = Point(x: 0, y: 0), secure: Bool = false) {
        self.control = control; self.rect = rect; self.caret = caret; self.text = text
        self.selection = selection; self.marked = marked; self.textOrigin = textOrigin
        self.secure = secure
    }

    public static func == (a: TextInput, b: TextInput) -> Bool {
        a.control == b.control && a.rect == b.rect && a.caret == b.caret && a.text == b.text
            && a.selection == b.selection && a.marked?.start == b.marked?.start
            && a.marked?.end == b.marked?.end && a.textOrigin == b.textOrigin && a.secure == b.secure
    }
}

public enum Cursor: UInt8, Sendable { case arrow, pointer, text }

// The outside world (lean/Cairn/Effects.lean, docs/effects.md).

/// The host's clock: monotonic ms (`CLOCK_MONOTONIC`), wall ms since the Unix epoch, and the
/// local zone's offset from UTC in seconds.
public struct Time: Equatable, Sendable {
    public var mono: UInt64
    public var wall: Int64
    public var zone: Int32
    public init(mono: UInt64, wall: Int64, zone: Int32) { self.mono = mono; self.wall = wall; self.zone = zone }
}

/// Why a request failed (`Cairn.Fault`).
public enum Fault: UInt8, Sendable { case notFound, denied, timeout, network, invalid, other }

public struct Header: Equatable, Sendable {
    public var name, value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}

/// A piece of an `upload` body (`Cairn.Part`).
public enum Part: Equatable, Sendable {
    case bytes([UInt8])
    /// Clip `clip`'s samples from 20 ms window `start` to window `stop` (the end when nil), as a
    /// 16 kHz mono 16-bit WAV file.
    case wav(clip: UInt32, start: UInt32, stop: UInt32?)
}

/// A header whose value the host reads from a secret (`Cairn.Secret`): `header: scheme value`,
/// where `value` comes from `source`.
public struct Secret: Equatable, Sendable {
    /// Where the value is (`Cairn.Secret.Source`).
    public enum Source: Equatable, Sendable {
        /// The environment variable `name`, or else `name`'s line in the `KEY=value` file `file`.
        case env(file: String, name: String)
        /// The generic password item `account` under the app's Keychain service.
        case keychain(account: String)
    }
    public var header, scheme: String
    public var source: Source
    public init(header: String, scheme: String, source: Source) {
        self.header = header; self.scheme = scheme; self.source = source
    }
    /// An environment secret (Yap's API key).
    public init(header: String, scheme: String, file: String, name: String) {
        self.init(header: header, scheme: scheme, source: .env(file: file, name: name))
    }
    /// Where it is, for messages: the variable's name or the item's account, never the value.
    public var label: String {
        switch source {
        case let .env(_, name): name
        case let .keychain(account): "Keychain item \(account)"
        }
    }
}

/// A top-level string field of a 2xx JSON reply that the host writes to Keychain item `account`
/// and blanks before Lean sees the body (`Request.http`'s `capture`).
public struct Capture: Equatable, Sendable {
    public var field, account: String
    public init(_ field: String, _ account: String) { self.field = field; self.account = account }
}

/// A TCC permission (`Cairn.Permission`).
public enum Permission: UInt8, Sendable { case accessibility, microphone }

/// Something the host does that answers back (`Cairn.Request`).
public enum Request: Equatable, Sendable {
    case readFile(path: String)
    /// Atomic replace, creating missing parent directories.
    case writeFile(path: String, data: [UInt8])
    case playSound(name: String)
    /// With a secret, its header is added as the request is sent; with captures, a 2xx JSON
    /// object reply's listed fields go to the Keychain and are blanked (docs/effects.md).
    /// `redact`: it carries a secret the person typed (a secure field's text); nothing prints its
    /// URL, headers or body.
    case http(method: String, url: String, headers: [Header], body: [UInt8], timeoutMs: UInt32,
              secret: Secret? = nil, capture: [Capture] = [], redact: Bool = false)
    /// Append, creating the file (mode 600) and missing parent directories.
    case appendFile(path: String, data: [UInt8])
    /// The names in a directory, sorted by their UTF-8 bytes.
    case listDir(path: String)
    /// Remove a file or symbolic link, never a directory.
    case deleteFile(path: String)
    /// The app in front: pid and name.
    case frontmostApp
    /// Whether the app holds a permission; `prompt` asks the person if not.
    case permission(Permission, prompt: Bool)
    /// Type `text` into app `pid`, activating it first, then press Return if asked.
    case typeText(pid: UInt32, text: String, pressReturn: Bool)
    /// An HTTP request whose body is assembled from parts and which may carry a secret header.
    case upload(method: String, url: String, headers: [Header], secret: Secret?, body: [Part], timeoutMs: UInt32)
    /// Drop a recorded clip's samples.
    case forgetClip(clip: UInt32)
    /// Open a path (`~/` is home) or a URL with its default app.
    case openItem(target: String)
    /// Whether an app with this bundle identifier is running.
    case appRunning(bundleId: String)
    /// A value from another domain's defaults, as text.
    case readDefault(domain: String, key: String)
    /// Create a directory and its missing parents, private (mode 700).
    case makeDir(path: String)
    /// Decode the image at a file path or http(s) URL, keep it for `image` draws naming the same
    /// source, and answer its pixel size. `reload` reads it again rather than answering from the
    /// cache.
    case loadImage(source: String, reload: Bool)
    /// Delete the Keychain item `account` (`done` when there is none).
    case forgetSecret(account: String)

    /// The kind code on the wire (`Request.Kind.code`).
    public var kindCode: UInt8 {
        switch self {
        case .readFile: 0
        case .writeFile: 1
        case .playSound: 2
        case .http: 3
        case .appendFile: 4
        case .listDir: 5
        case .deleteFile: 6
        case .frontmostApp: 7
        case .permission: 8
        case .typeText: 9
        case .upload: 10
        case .forgetClip: 11
        case .openItem: 12
        case .appRunning: 13
        case .readDefault: 14
        case .makeDir: 15
        case .loadImage: 16
        case .forgetSecret: 17
        }
    }
}

public enum Reply: Equatable, Sendable {
    case done
    case bytes([UInt8])
    case http(status: UInt32, headers: [Header], body: [UInt8])
    case failed(Fault, String)
    /// `listDir`'s names.
    case names([String])
    /// `frontmostApp`'s pid and name ("" when it has none).
    case app(pid: UInt32, name: String)
    /// `permission`'s answer.
    case flag(Bool)
    /// `loadImage`'s pixel size.
    case image(width: UInt32, height: UInt32)

    /// `done` 0, `bytes` 1, `http` 2, `failed` 3, `names` 4, `app` 5, `flag` 6, `image` 7
    /// (`Reply.code`).
    public var code: UInt8 {
        switch self {
        case .done: 0
        case .bytes: 1
        case .http: 2
        case .failed: 3
        case .names: 4
        case .app: 5
        case .flag: 6
        case .image: 7
        }
    }
}

public enum Sub: Hashable, Sendable {
    /// A tick every `ms` milliseconds.
    case every(ms: UInt32)
    /// `changed` whenever the file changes.
    case watchFile(path: String)
    /// Record the microphone into clip `clip`, streaming levels.
    case record(clip: UInt32)
    /// The hotkey: a key code, or a modifier key (its code and its modifier flag bit).
    case globalKey(code: UInt32, modifier: UInt32?)
    /// Keep decoded images within about `bytes` bytes, reporting each one dropped (`evicted`).
    case imageCache(bytes: UInt64)
}

/// One 20 ms window of a recording (`Cairn.Level`).
public struct Level: Equatable, Sendable {
    public var sumSq: UInt64
    public var peak: UInt32
    public init(sumSq: UInt64, peak: UInt32) { self.sumSq = sumSq; self.peak = peak }
}

/// What an active subscription reports (`Cairn.SubEvent`).
public enum SubEvent: Equatable, Sendable {
    case tick, changed
    case audio(frames: UInt32, peak: UInt32, windows: [Level])
    /// Monotonic milliseconds.
    case keyDown(UInt64), keyUp(UInt64), otherKey(UInt64)
    case failed(Fault, String)
    /// `record`: the microphone is running, since these monotonic milliseconds. Once, before
    /// any `audio`.
    case started(UInt64)
    /// `imageCache`: the host dropped this source's pixels.
    case evicted(String)

    /// `tick` 0, `changed` 1, `audio` 2, `keyDown` 3, `keyUp` 4, `otherKey` 5, `failed` 6,
    /// `started` 7, `evicted` 8.
    public var code: UInt8 {
        switch self {
        case .tick: 0
        case .changed: 1
        case .audio: 2
        case .keyDown: 3
        case .keyUp: 4
        case .otherKey: 5
        case .failed: 6
        case .started: 7
        case .evicted: 8
        }
    }

    /// Carries nothing but that it happened, so repeats can be merged.
    public var isSignal: Bool { self == .tick || self == .changed }
}

/// Lean → host: start or stop a subscription under Lean's id for it.
public enum SubCmd: Equatable, Sendable {
    case start(id: UInt32, Sub)
    case stop(id: UInt32)
}

public enum Effect: Equatable, Sendable {
    case setClipboard(String)
    case beep
    /// Run by Lean's runtime (it moves keyboard focus); the host has nothing to do.
    case focus(ControlRef)
    /// Timers live in Lean's runtime (the frame's `wake` is the earliest deadline); the host
    /// has nothing to do with these but show them in the debug log.
    case setTimer(name: String, ms: UInt32)
    case cancelTimer(String)
    /// Run it and answer with `Event.reply(id:)`, once.
    case request(id: UInt32, Request)
    /// Quit the app.
    case quit
    /// Stop the work of request `id` if it is still running (`URLSession` task cancel); it is
    /// still answered once, and Lean's runtime drops that reply (^1009).
    case cancelRequest(id: UInt32)
    /// Run by Lean's runtime (it moves a scroll offset); the host has nothing to do.
    case scrollTo(ControlRef, ScrollTarget)
    /// Set the Dock tile's badge to exactly this label; `nil` clears it.
    case badge(String?)
    /// Post an accessibility announcement of exactly this text, once.
    case announce(String, priority: Priority)
}

/// Where `Effect.scrollTo` moves a box (Lean's runtime runs it).
public enum ScrollTarget: Equatable, Sendable {
    case start
    case finish
    case key(UInt32)
}

/// An announcement's priority: `low` waits for speech in progress, `high` interrupts it.
public enum Priority: UInt8, Equatable, Sendable {
    case low = 0
    case high = 1
}

/// What one Metal surface (the window, a panel) shows (`Cairn.Canvas`).
public struct Canvas: Equatable, Sendable {
    public var size: Size
    public var draws: [Draw]
    public var ax: [AxNode]
    public var textInput: TextInput?
    public var cursor: Cursor
    public init(size: Size, draws: [Draw], ax: [AxNode] = [], textInput: TextInput? = nil,
                cursor: Cursor = .arrow) {
        self.size = size; self.draws = draws; self.ax = ax; self.textInput = textInput
        self.cursor = cursor
    }
    public static let empty = Canvas(size: Size(w: 0, h: 0), draws: [])
}

public enum SurfaceKind: UInt8, Sendable { case window, panel, statusItem, menuBar }
public enum MenuKind: UInt8, Sendable { case item, info, submenu, separator }
/// Which screen a panel is shown on.
public enum ScreenChoice: UInt8, Sendable { case pointer, main }

/// Where a panel goes on its screen (`Cairn.Anchor`).
public enum Anchor: Equatable, Sendable {
    /// Horizontally centred, `offset` points above the bottom of the visible frame.
    case bottomCenter(offset: UInt32)
    public var code: UInt8 { switch self { case .bottomCenter: 0 } }
    public var offset: UInt32 { switch self { case let .bottomCenter(o): o } }
}

public struct Shortcut: Equatable, Sendable {
    public var key: Key
    public var mods: Mods
    public init(key: Key, mods: Mods) { self.key = key; self.mods = mods }
}

/// One menu item, flattened (`Frame.ofMenu`): parents come before children.
public struct MenuRecord: Equatable, Sendable {
    public var kind: MenuKind
    public var label: String
    public var control: ControlRef?
    /// A submenu's place claim.
    public var place: UInt32?
    /// Index of the enclosing submenu's record.
    public var parent: Int?
    public var enabled: Bool
    public var checked: Bool?
    public var shortcut: Shortcut?
    public init(kind: MenuKind, label: String = "", control: ControlRef? = nil, place: UInt32? = nil,
                parent: Int? = nil, enabled: Bool = true, checked: Bool? = nil,
                shortcut: Shortcut? = nil) {
        self.kind = kind; self.label = label; self.control = control; self.place = place
        self.parent = parent; self.enabled = enabled; self.checked = checked; self.shortcut = shortcut
    }
}

/// A status item's button and menu.
public struct StatusFrame: Equatable, Sendable {
    public var control: ControlRef
    public var symbol: String
    public var title: String
    public var label: String
    public var menu: [MenuRecord]
    public init(control: ControlRef = ControlRef(claim: 0), symbol: String = "", title: String = "",
                label: String = "", menu: [MenuRecord] = []) {
        self.control = control; self.symbol = symbol; self.title = title; self.label = label
        self.menu = menu
    }
}

/// One surface's record (docs/frame.md). Fields a kind doesn't use are at their defaults.
public struct Surface: Equatable, Sendable {
    public var kind: SurfaceKind
    /// The surface's place claim: its identity.
    public var place: UInt32
    public var shown: Bool
    public var title: String
    public var anchor: Anchor
    public var screen: ScreenChoice
    /// The window's smallest content size, in points (`App.minSize`); 0 × 0 for other kinds.
    /// The host keeps the window at least this big (^1010).
    public var minSize: Size
    public var canvas: Canvas
    public var status: StatusFrame
    public init(kind: SurfaceKind, place: UInt32, shown: Bool = true, title: String = "",
                anchor: Anchor = .bottomCenter(offset: 0), screen: ScreenChoice = .pointer,
                minSize: Size = Size(w: 0, h: 0), canvas: Canvas = .empty, status: StatusFrame = StatusFrame()) {
        self.kind = kind; self.place = place; self.shown = shown; self.title = title
        self.anchor = anchor; self.screen = screen; self.minSize = minSize; self.canvas = canvas
        self.status = status
    }
}

public struct Frame: Equatable, Sendable {
    /// Every surface of the app, in the app's order.
    public var surfaces: [Surface]
    public var effects: [Effect]
    /// Subscriptions to start and stop, in order.
    public var subs: [SubCmd]
    /// Send a clock event once the monotonic clock reaches this (ms): the earliest timer.
    public var wake: UInt64?
    public init(surfaces: [Surface], effects: [Effect] = [], subs: [SubCmd] = [], wake: UInt64? = nil) {
        self.surfaces = surfaces; self.effects = effects; self.subs = subs; self.wake = wake
    }
    /// A frame with one window (place 0): M1's frame (`Frame.single`).
    public init(size: Size, draws: [Draw], ax: [AxNode] = [], textInput: TextInput? = nil,
                cursor: Cursor = .arrow, effects: [Effect] = [], subs: [SubCmd] = [],
                wake: UInt64? = nil) {
        let c = Canvas(size: size, draws: draws, ax: ax, textInput: textInput, cursor: cursor)
        self.init(surfaces: [Surface(kind: .window, place: 0, canvas: c)], effects: effects,
                  subs: subs, wake: wake)
    }

    /// The sources of every `image` draw, on every surface.
    public var imageSources: Set<String> {
        var out: Set<String> = []
        for s in surfaces {
            for d in s.canvas.draws { if case let .image(_, _, source) = d { out.insert(source) } }
        }
        return out
    }

    /// The index of the first window, if any.
    public var windowIndex: Int? { surfaces.firstIndex { $0.kind == .window } }

    /// The first window's canvas; empty when there is none. Setting it with no window adds one.
    public var window: Canvas {
        get { windowIndex.map { surfaces[$0].canvas } ?? .empty }
        set {
            if let i = windowIndex { surfaces[i].canvas = newValue }
            else { surfaces.insert(Surface(kind: .window, place: 0, canvas: newValue), at: 0) }
        }
    }
    public var size: Size { get { window.size } set { window.size = newValue } }
    public var draws: [Draw] { get { window.draws } set { window.draws = newValue } }
    public var ax: [AxNode] { get { window.ax } set { window.ax = newValue } }
    public var textInput: TextInput? { get { window.textInput } set { window.textInput = newValue } }
    public var cursor: Cursor { get { window.cursor } set { window.cursor = newValue } }

    /// The surface with this place.
    public func surface(_ place: UInt32) -> Surface? { surfaces.first { $0.place == place } }
}

public struct Mods: Equatable, Sendable {
    public var shift = false, command = false, option = false, control = false
    public init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift; self.command = command; self.option = option; self.control = control
    }
}

/// `[start, end)` in Unicode scalar indices into a field's text (Lean's `Nat × Nat`).
public struct ScalarRange: Equatable, Hashable, Sendable {
    public var start, end: UInt32
    public init(start: UInt32, end: UInt32) { self.start = start; self.end = end }
}

public enum Button: UInt8, Sendable { case primary, secondary }

public enum Key: Equatable, Sendable {
    case enter, escape, tab, backspace, delete
    case left, right, up, down, home, finish, pageUp, pageDown
    case char(Character)
    /// The context-menu key: Shift-F10, or the Menu key of a PC keyboard.
    case menu
}

public enum Event: Equatable, Sendable {
    case pointerMove(Point)
    case pointerDown(Point, Button, clicks: UInt32, Mods)
    case pointerUp(Point, Button, Mods)
    case pointerExit
    case scroll(Point, dx: Int32, dy: Int32)
    case key(Key, Mods)
    /// Committed text. Replaces `replacing` when given, else the marked text, else the selection.
    case insertText(String, replacing: ScalarRange? = nil)
    /// Composition: marked text with a selection inside it (scalar offsets into `s`), replacing
    /// `replacing`, else the marked text, else the selection. Empty `s` ends the composition.
    case setMarked(String, selStart: UInt32, selLen: UInt32, replacing: ScalarRange? = nil)
    case unmark
    case copy, cut, selectAll, undo, redo
    case paste(String)
    case resize(Size)
    case scale(percent: UInt32)
    case windowFocus(Bool)
    /// The time. The host sends one first in every batch (docs/effects.md).
    case clock(Time)
    case reply(id: UInt32, Reply)
    case subEvent(id: UInt32, SubEvent)
    /// A surface-local event for the surface whose place is `place`. A bare local event is the
    /// window's (M1).
    indirect case surface(place: UInt32, Event)
    /// The status item's menu is opening (`menuWillOpen`).
    case menuOpen(place: UInt32)
    /// The status item's menu closed (`menuDidClose`).
    case menuClose(place: UInt32)
    /// The person chose the item `ref` in the status item's menu.
    case menuSelect(place: UInt32, ControlRef)
}

