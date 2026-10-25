import Carbon.HIToolbox
import CairnFrame
import CairnHost
import Foundation

/// Secure event input (^1020, `SecureInputGate` in host/Sources/CairnHost/SecureInput.swift).
/// Each case runs a random sequence of the host's states: the applied frame's text input (none,
/// a plain field, a secure field), whether the window is key, whether the view is live (in a
/// window, not shut down), each given to the gate as `HostView.updateSecureInput` gives it.
/// Most cases record the gate's calls; some use the system's own calls (`EnableSecureEventInput`,
/// `DisableSecureEventInput`) and read `IsSecureEventInputEnabled` back. After every step:
///
/// - `text.secure-input`: the gate is on exactly when the view is live, its window is key and
///   the text input is a secure field; its calls alternate on, off, on, starting with on, so
///   the system's count of enables never goes past one or below zero; with the system's calls,
///   secure input reads as enabled while the gate is on, and once the gate is off it reads as it
///   did before the case (another process may hold it on; this one never leaves it on).
final class SecureInputSuite: Suite {
    let name = "secure-input"
    let crashCheck = "text.secure-input"
    let checks: [String: CheckInfo] = [
        "text.secure-input": CheckInfo(
            title: "Secure event input is on exactly while a secure field has focus",
            trusted: ["host/Sources/CairnHost/SecureInput.swift (SecureInputGate)",
                      "host/Sources/CairnHost/HostView.swift (updateSecureInput and its call sites)",
                      "Carbon (EnableSecureEventInput, DisableSecureEventInput, IsSecureEventInputEnabled)"],
            oracle: "the frame's TextInput.secure, the window's key state and the view's life, step by step"),
    ]

    func cases(for n: Int) -> Int { max(8, n) }
    func setUp() {}

    enum Field: CustomStringConvertible {
        case none, plain, secure
        var description: String {
            switch self { case .none: "no field"; case .plain: "a plain field"; case .secure: "a secure field" }
        }
    }

    struct Step: CustomStringConvertible {
        var field: Field
        var key: Bool
        var live: Bool
        var description: String { "\(field), window \(key ? "key" : "not key"), view \(live ? "live" : "not live")" }
    }

    static func plan(_ g: inout SplitMix) -> (system: Bool, steps: [Step]) {
        let system = g.chance(1, 8)
        var steps: [Step] = []
        for _ in 0..<g.range(1, 30) {
            steps.append(Step(field: g.weighted([(2, { _ in .none }), (2, { _ in .plain }), (3, { _ in .secure })]),
                              key: g.chance(3, 4), live: g.chance(7, 8)))
        }
        // End as a closed window does, so a case never leaves secure input on.
        steps.append(Step(field: steps.last!.field, key: false, live: false))
        return (system, steps)
    }

    static func textInput(_ f: Field) -> TextInput? {
        switch f {
        case .none: return nil
        case .plain, .secure:
            return TextInput(control: ControlRef(claim: 9), rect: Rect(x: 0, y: 0, w: 100, h: 20),
                             caret: Rect(x: 0, y: 0, w: 1, h: 16), text: f == .secure ? "\u{2022}\u{2022}" : "ab",
                             selection: (2, 2), marked: nil, secure: f == .secure)
        }
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Bool] = []
        func add(_ b: Bool) { lock.withLock { list.append(b) } }
        var all: [Bool] { lock.withLock { list } }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let (system, steps) = Self.plan(&g)
        let calls = Calls()
        let before = SecureInputGate.systemEnabled
        var gate = SecureInputGate(toggle: { on in
            calls.add(on)
            if system { SecureInputGate.system(on) }
        })
        r.ran("text.secure-input")
        if system { r.count("text.secure-input", "cases with the system's calls") }
        for (i, s) in steps.enumerated() {
            let want = s.live && s.key && s.field == .secure
            if SecureInputGate.wanted(textInput: Self.textInput(s.field), windowKey: s.key, live: s.live) != want {
                r.fail("text.secure-input", "step \(i) (\(s)): wanted says \(!want), want \(want)")
                return
            }
            gate.set(SecureInputGate.wanted(textInput: Self.textInput(s.field), windowKey: s.key, live: s.live))
            if gate.on != want {
                r.fail("text.secure-input", "step \(i) (\(s)): the gate is \(gate.on ? "on" : "off"), want \(want ? "on" : "off")")
                return
            }
            let made = calls.all
            for (j, c) in made.enumerated() where c != (j % 2 == 0) {
                r.fail("text.secure-input", "step \(i) (\(s)): call \(j) turns it \(c ? "on" : "off"); calls must alternate, starting with on: \(made)")
                return
            }
            if (made.last ?? false) != want {
                r.fail("text.secure-input", "step \(i) (\(s)): the last call left it \((made.last ?? false) ? "on" : "off"), want \(want ? "on" : "off")")
                return
            }
            if system {
                let now = SecureInputGate.systemEnabled
                if want && !now {
                    r.fail("text.secure-input", "step \(i) (\(s)): the gate is on, but IsSecureEventInputEnabled says off")
                    return
                }
                if !want && now != before {
                    r.fail("text.secure-input", "step \(i) (\(s)): the gate is off, but IsSecureEventInputEnabled says \(now), and said \(before) before the case")
                    return
                }
            }
            if want { r.count("text.secure-input", "steps on") }
        }
        r.count("text.secure-input", "toggles", calls.all.count)
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (system, steps) = Self.plan(&g)
        return (system ? "with the system's calls: " : "") + steps.map(\.description).joined(separator: "; ")
    }
}
