import AppKit
import ApplicationServices
import CairnFrame
import Foundation

// The `globalKey` subscription and the `typeText` request (docs/effects.md). Trusted: claims
// ^969 and ^970 in docs/trusted.md. Both need Accessibility; without it they fail `denied`
// and touch nothing. The logic (which events are a press, how text is split into key events)
// is pure and fuzzed; the system calls sit behind small structs of functions.

// MARK: globalKey

/// One key event as the monitors see it.
public struct KeyEventIn: Sendable, Equatable {
    public enum Kind: Sendable { case flagsChanged, keyDown, keyUp }
    public var kind: Kind
    public var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`.
    public var flags: UInt
    public var isRepeat: Bool
    /// Monotonic milliseconds (`HostClock.monoMs`) when it happened.
    public var t: UInt64

    public init(kind: Kind, keyCode: UInt16, flags: UInt, isRepeat: Bool, t: UInt64) {
        self.kind = kind; self.keyCode = keyCode; self.flags = flags; self.isRepeat = isRepeat; self.t = t
    }
}

/// Yap's PushToTalk.handle: the hotkey's press and release, and other keys pressed while it is
/// held. A modifier hotkey is told pressed from released by its flag in `flagsChanged`; an
/// ordinary key by key down (not repeats) and key up.
public struct KeyWatch: Sendable {
    public let code: UInt16
    public let modifier: UInt?
    public private(set) var isDown = false

    public init(code: UInt16, modifier: UInt?) { self.code = code; self.modifier = modifier }

    public mutating func handle(_ e: KeyEventIn) -> SubEvent? {
        let ours = e.keyCode == code
        switch e.kind {
        case .flagsChanged:
            guard ours, let flag = modifier else { return nil }
            return set(e.flags & flag != 0, e.t)
        case .keyDown where ours && modifier == nil:
            guard !e.isRepeat else { return nil }
            return set(true, e.t)
        case .keyUp where ours && modifier == nil:
            return set(false, e.t)
        case .keyDown where isDown:
            return .otherKey(e.t)
        default:
            return nil
        }
    }

    private mutating func set(_ down: Bool, _ t: UInt64) -> SubEvent? {
        guard down != isDown else { return nil }
        isDown = down
        return down ? .keyDown(t) : .keyUp(t)
    }
}

/// Where key events come from. `start` delivers every key event to the handler until the
/// returned stop runs.
public struct KeySource: Sendable {
    public var trusted: @Sendable () -> Bool
    public var start: @Sendable (_ handler: @escaping @Sendable (KeyEventIn) -> Void) -> @Sendable () -> Void

    public init(trusted: @escaping @Sendable () -> Bool,
                start: @escaping @Sendable (@escaping @Sendable (KeyEventIn) -> Void) -> @Sendable () -> Void) {
        self.trusted = trusted
        self.start = start
    }

    /// Global and local NSEvent monitors (local too, so the key works while the app's own
    /// window or menu has focus), installed and removed on the main thread.
    public static let live = KeySource(trusted: { AXIsProcessTrusted() }) { handler in
        let monitors = Guarded<[Any]>([])
        let stopped = Guarded(false)
        DispatchQueue.main.async {
            guard !stopped.value else { return }
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
            let h: (NSEvent) -> Void = { ev in handler(KeySource.convert(ev)) }
            monitors.value = [
                NSEvent.addGlobalMonitorForEvents(matching: mask, handler: h),
                NSEvent.addLocalMonitorForEvents(matching: mask) { h($0); return $0 },
            ].compactMap { $0 }
        }
        return {
            DispatchQueue.main.async {
                stopped.value = true
                for m in monitors.value { NSEvent.removeMonitor(m) }
                monitors.value = []
            }
        }
    }

    /// The event's time on the monotonic clock: NSEvent times count from boot on the uptime
    /// clock, which stops during sleep, so the event's age is subtracted from now instead.
    @MainActor static func convert(_ ev: NSEvent) -> KeyEventIn {
        let age = max(0, ProcessInfo.processInfo.systemUptime - ev.timestamp)
        let now = HostClock.monoMs()
        let kind: KeyEventIn.Kind = switch ev.type {
        case .flagsChanged: .flagsChanged
        case .keyDown: .keyDown
        default: .keyUp
        }
        return KeyEventIn(kind: kind, keyCode: ev.keyCode, flags: ev.modifierFlags.rawValue,
                          isRepeat: ev.type == .keyDown && ev.isARepeat,
                          t: now - min(now, UInt64(age * 1000)))
    }
}

/// A value behind a lock.
final class Guarded<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
    func update<R>(_ f: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(&v) }
}

// MARK: typeText

/// The system calls behind `typeText`.
public struct Typist: Sendable {
    public var trusted: @Sendable () -> Bool
    /// Whether a process with this pid is a running app.
    public var exists: @Sendable (pid_t) -> Bool
    /// Brings the app forward and waits up to `timeout` seconds; true once it is in front.
    public var activate: @Sendable (pid_t, _ timeout: Double) -> Bool
    /// Posts each run as a key down and up carrying its UTF-16 units, pausing between them,
    /// then Return when asked.
    public var post: @Sendable (_ runs: [[UInt16]], _ pressReturn: Bool) -> Void

    public init(trusted: @escaping @Sendable () -> Bool, exists: @escaping @Sendable (pid_t) -> Bool,
                activate: @escaping @Sendable (pid_t, Double) -> Bool,
                post: @escaping @Sendable ([[UInt16]], Bool) -> Void) {
        self.trusted = trusted; self.exists = exists; self.activate = activate; self.post = post
    }

    /// Yap's TextInjector: synthesized key events with a Unicode payload (virtual key 0), one
    /// event source for the burst, 4 ms between events, Return as key code 36, posted at the
    /// HID tap.
    public static let live = Typist(
        trusted: { AXIsProcessTrusted() },
        exists: { pid in DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid) != nil } },
        activate: { pid, timeout in
            let deadline = Date().addingTimeInterval(timeout)
            let active: @Sendable () -> Bool? = {
                DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid)?.isActive }
            }
            guard let now = active() else { return false }
            if now { return true }
            DispatchQueue.main.sync { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
            while Date() < deadline {
                if active() == true { return true }
                usleep(25_000)
            }
            return active() == true
        },
        post: { runs, ret in
            let source = CGEventSource(stateID: .hidSystemState)
            for units in runs {
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                usleep(Typing.pauseMicros)
            }
            if ret {
                CGEvent(keyboardEventSource: source, virtualKey: Typing.returnKey, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: Typing.returnKey, keyDown: false)?.post(tap: .cghidEventTap)
            }
        })
}

public enum Typing {
    /// UTF-16 units per key event: the payload is a fixed-size buffer.
    public static let unitsPerEvent = 20
    public static let pauseMicros: useconds_t = 4000
    public static let returnKey: CGKeyCode = 36
    /// How long the app has to come forward.
    public static let activationTimeout = 0.6

    /// The text as per-event payloads, never splitting a character (half an emoji is not a
    /// character). A character longer than a payload is a run of its own.
    public static func runs(of text: String) -> [[UInt16]] {
        var runs: [[UInt16]] = []
        var current: [UInt16] = []
        for ch in text {
            let units = Array(ch.utf16)
            if current.count + units.count > unitsPerEvent, !current.isEmpty {
                runs.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Types `text` into app `pid`: `invalid` for no text, `denied` without Accessibility,
    /// `notFound` for no such app, `other` when it would not come forward. Only then is
    /// anything posted; typing into whatever happens to be in front would put the words in the
    /// wrong window.
    public static func type(pid: UInt32, text: String, pressReturn: Bool, _ t: Typist) -> Reply {
        guard !text.isEmpty else { return .failed(.invalid, "nothing to type") }
        guard t.trusted() else { return .failed(.denied, "Accessibility is not granted, so the app cannot type") }
        guard pid > 0, pid <= UInt32(Int32.max), t.exists(pid_t(pid)) else {
            return .failed(.notFound, "no app with pid \(pid)")
        }
        guard t.activate(pid_t(pid), activationTimeout) else {
            return .failed(.other, "app \(pid) would not come to the front")
        }
        t.post(runs(of: text), pressReturn)
        return .done
    }
}
