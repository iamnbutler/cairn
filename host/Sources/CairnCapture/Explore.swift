import CairnFrame
import CairnHost
import CairnRender
import CoreGraphics
import Foundation

/// The states behind a "Try it" page (docs/try.md; the site's /try/ pages, made by `make try`).
///
/// A bounded breadth-first walk of an app's real `step` and `frame`, headless like the map capture:
/// from the initial frame, act on every control in the frame's accessibility nodes with each
/// action its claim allows (the script lists them per claim, from the claims export), take the
/// next frame, and keep it as a new state unless an earlier state has the same window (draws,
/// accessibility nodes, text input and cursor). Nothing here decides what an action does: each
/// state is reached by replaying its path from a fresh start, and the edge records whatever frame
/// the app produced.
///
///     <App> --try-capture <script.json> <out dir>
///
/// writes `try.json` and one PNG per state (unpinned), all cropped to one rect.
enum TryCapture {
    struct Script: Decodable {
        var scale: Float?
        /// States further than this many actions from the start are not kept.
        var maxDepth: Int
        /// At most this many states in all.
        var maxStates: Int
        /// The actions each claim's controls take, by claim id.
        var actions: [String: [Action]]
    }
    /// One thing a person can do to a control: one or more capture steps, sent in order, with the
    /// frame recorded only after the last.
    struct Action: Codable {
        var label: String
        var steps: [MapCapture.Gesture]
    }

    struct Control: Encodable {
        var ref: String, claim: UInt32, key: UInt32
        var role: String, label: String, value: String
        var rect: [Int32]
        var focused: Bool, selected: Bool, checked: Bool?
    }
    struct Edge: Encodable {
        var ref: String
        /// Index into the claim's actions.
        var action: Int
        /// The state it leads to; nil when it is `inert` or `beyond`.
        var to: Int?
        /// `ok`, `inert` (the frame didn't change), `beyond` (a new frame past the bound) or
        /// `unsupported` (a step the capture can't send).
        var outcome: String
    }
    struct State: Encodable {
        var id: Int
        var depth: Int
        var image: String
        var width: Int, height: Int
        /// The edge that first reached this state: (from, edge index); nil for the start.
        var from: [Int]?
        var focus: String?
        var text: String?
        var controls: [Control]
        var edges: [Edge]
    }
    struct Output: Encodable {
        var size: [Int32], scale: Float
        var crop: [Int32]
        var maxDepth: Int, maxStates: Int
        var actions: [String: [Action]]
        var states: [State]
    }

    static func main(_ args: [String], size: Size, core: @escaping () -> AppCore) -> Int32? {
        guard let i = args.firstIndex(of: "--try-capture") else { return nil }
        guard i + 2 < args.count else {
            FileHandle.standardError.write("usage: --try-capture <script.json> <out dir>\n".data(using: .utf8)!)
            return 2
        }
        do {
            let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
            try run(script, size: size, core: core, out: URL(fileURLWithPath: args[i + 2], isDirectory: true))
            return 0
        } catch {
            FileHandle.standardError.write("try capture: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }

    /// One step of a path: the control (by ref) and which of its claim's actions.
    struct Move { var ref: ControlRef; var action: Int }

    static func run(_ script: Script, size: Size, core make: @escaping () -> AppCore, out: URL) throws {
        let scale = script.scale ?? 2
        let t0 = Date()
        // The walk, on one Lean thread with one core: `start` again resets it to the initial state.
        let (canvases, paths, edges, depths) = try MapCapture.onLeanThread { () throws -> ([Canvas], [[Move]], [[Edge]], [Int]) in
            let app = make()
            func reach(_ path: [Move]) throws -> Frame {
                app.start(size: size, scalePercent: UInt32(scale * 100))
                for m in path {
                    let f = try app.frame()
                    guard let node = f.ax.first(where: { $0.control == m.ref }),
                          let action = script.actions[String(m.ref.claim)]?[m.action] else {
                        throw CocoaError(.validationMissingMandatoryProperty)  // a recorded path no longer replays
                    }
                    try perform(action, on: node, in: app)
                }
                return try app.frame()
            }
            var canvases = [try reach([]).window]
            var paths: [[Move]] = [[]]
            var depths = [0]
            var edges: [[Edge]] = []
            var k = 0
            while k < canvases.count {
                let here = canvases[k]
                var out: [Edge] = []
                for node in here.ax {
                    guard let ref = node.control else { continue }
                    for (a, action) in (script.actions[String(ref.claim)] ?? []).enumerated() {
                        let path = paths[k] + [Move(ref: ref, action: a)]
                        let before = try reach(paths[k])
                        guard let n = before.ax.first(where: { $0.control == ref }) else { continue }
                        guard (try? perform(action, on: n, in: app)) != nil else {
                            out.append(Edge(ref: ref.label, action: a, to: nil, outcome: "unsupported"))
                            continue
                        }
                        let next = try app.frame().window
                        if next == here {
                            out.append(Edge(ref: ref.label, action: a, to: nil, outcome: "inert"))
                        } else if let j = canvases.firstIndex(of: next) {
                            out.append(Edge(ref: ref.label, action: a, to: j, outcome: "ok"))
                        } else if depths[k] + 1 <= script.maxDepth && canvases.count < script.maxStates {
                            canvases.append(next); paths.append(path); depths.append(depths[k] + 1)
                            out.append(Edge(ref: ref.label, action: a, to: canvases.count - 1, outcome: "ok"))
                        } else {
                            out.append(Edge(ref: ref.label, action: a, to: nil, outcome: "beyond"))
                        }
                    }
                }
                edges.append(out)
                k += 1
            }
            return (canvases, paths, edges, depths)
        }
        let walked = Date().timeIntervalSince(t0)

        // Render each state; one crop for all (what was painted and every control, padded).
        let renderer = try Renderer()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var images: [Image] = []
        var ink: CGRect = .null
        for c in canvases {
            let frame = Frame(surfaces: [Surface(kind: .window, place: 0, canvas: c)])
            let img = try renderer.image(frame, scale: scale)
            ink = ink.union(MapCapture.inkBounds(img, scale: CGFloat(scale)))
            for n in c.ax where n.control != nil {
                ink = ink.union(CGRect(x: CGFloat(n.rect.x), y: CGFloat(n.rect.y), width: CGFloat(n.rect.w), height: CGFloat(n.rect.h)))
            }
            images.append(img)
        }
        let window = CGRect(x: 0, y: 0, width: CGFloat(size.w), height: CGFloat(size.h))
        let crop = ink.isNull ? window : ink.insetBy(dx: -16, dy: -16).integral.intersection(window)
        let px = CGRect(x: crop.minX * CGFloat(scale), y: crop.minY * CGFloat(scale),
                        width: crop.width * CGFloat(scale), height: crop.height * CGFloat(scale)).integral

        // The edge that first reached each state, for the page's "how you got here".
        var firstIn = [[Int]?](repeating: nil, count: canvases.count)
        for (k, es) in edges.enumerated() {
            for (e, edge) in es.enumerated() where edge.to != nil && edge.to! > k && firstIn[edge.to!] == nil {
                firstIn[edge.to!] = [k, e]
            }
        }
        var states: [State] = []
        for (k, c) in canvases.enumerated() {
            let name = "state-\(k).png"
            try MapCapture.write(MapCapture.opaque(images[k].cgImage()).cropping(to: px)!, to: out.appendingPathComponent(name))
            let controls = c.ax.compactMap { n -> Control? in
                guard let r = n.control else { return nil }
                return Control(ref: r.label, claim: r.claim, key: r.key, role: "\(n.role)", label: n.label, value: n.value,
                               rect: [n.rect.x, n.rect.y, n.rect.w, n.rect.h], focused: n.focused, selected: n.selected, checked: n.checked)
            }
            states.append(State(id: k, depth: depths[k], image: name, width: Int(px.width), height: Int(px.height),
                                from: firstIn[k], focus: c.textInput?.control.label, text: c.textInput?.text,
                                controls: controls, edges: edges[k]))
        }
        _ = paths
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(Output(size: [size.w, size.h], scale: scale,
                              crop: [Int32(crop.minX), Int32(crop.minY), Int32(crop.width), Int32(crop.height)],
                              maxDepth: script.maxDepth, maxStates: script.maxStates, actions: script.actions, states: states))
            .write(to: out.appendingPathComponent("try.json"))
        let n = edges.reduce(0) { $0 + $1.count }
        let beyond = edges.reduce(0) { $0 + $1.filter { $0.outcome == "beyond" }.count }
        print(String(format: "try capture: %d states, %d edges (%d beyond the bound), walked in %.1f s", states.count, n, beyond, walked))
    }

    /// Sends an action's steps to the control `node`, each from the frame the last one left.
    static func perform(_ action: Action, on node: AxNode, in app: AppCore) throws {
        guard let ref = node.control else { return }
        for step in action.steps {
            let f = try app.frame()
            guard let n = f.ax.first(where: { $0.control == ref }) ?? (f.textInput?.control == ref ? node : nil),
                  let events = MapCapture.events(trigger: step.trigger, op: step.op, node: n, frame: f) else {
                throw CocoaError(.featureUnsupported)
            }
            app.step(events)
        }
    }
}
