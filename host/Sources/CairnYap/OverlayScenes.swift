import CairnFrame
import CairnHost
import CairnRender
import CairnYapPaint
import CLean
import Foundation

/// `CairnYap --overlay-scenes <scenes.json> <out dir>`: the overlay rendered offscreen in given
/// states, for comparison with the original's (docs/yap.md, "Overlay parity").
///
/// Each state is the original reference harness's (`phase`, `text`, `clockSeconds`, `time`,
/// `elapsed`, `cuts`): Lean lays the panel out as the app does (`cairn_yap_overlay_frame`) and the
/// renderer draws it, tape included, at the given time. The levels are the harness's recipe,
/// `level(t) = min(1, 0.15 + |sin 9t| (0.55 + 0.45 sin 1.7t) 0.8)`, heard once a frame at 60 Hz
/// from the start of the recording; the tape rebuilds the original's 60 Hz history from them,
/// which is checked against the harness's own `levels`.
enum OverlayScenes {
    struct Scenes: Decodable { var states: [State] }
    struct State: Decodable {
        var name: String
        var phase: String
        var text: String
        var clockSeconds: Double
        var time: Double
        var elapsed: Double
        var levels: [Float]
        var cuts: [Double]
    }

    static func level(_ t: Double) -> Double { min(1, 0.15 + abs(sin(9 * t)) * (0.55 + 0.45 * sin(1.7 * t)) * 0.8) }

    static func scene(_ s: State) -> (bytes: [UInt8], nowMs: UInt32) {
        var out: [UInt8] = []
        func word(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out += $0 } }
        let look: UInt32 = ["listening": 0, "handsFree": 1, "transcribing": 2, "typed": 3, "failed": 4][s.phase] ?? 0
        let live = look < 2
        // On the host's clock: now 100 s; the recording began `elapsed` ago and the tape's clock
        // `time` ago. Stopped phases stopped now.
        let now: UInt32 = 100_000
        let since = now - UInt32((s.elapsed * 1000).rounded())
        let epoch = now - UInt32((s.time * 1000).rounded())
        word(look); word(since); word(epoch); word(now); word(live ? 0xFFFF_FFFF : now)
        let text = Array(s.text.utf8)
        word(UInt32(text.count)); out += text
        let n = Int((s.elapsed * 60).rounded())
        word(UInt32(n))
        for k in 1...n {
            word(since + UInt32((Double(k) * 1000 / 60).rounded()))
            word(UInt32((Double(Float(level(Double(k) / 60))) * 1e6).rounded()))
        }
        word(UInt32(s.cuts.count))
        for c in s.cuts { word(UInt32((c * 16000).rounded())) }
        return (out, now)
    }

    static func frame(_ bytes: [UInt8]) throws -> Frame {
        let r = cairn_yap_overlay_frame(LeanRuntime.bytes(bytes))!
        return try LeanRuntime.withBytes(r) { try Frame(decoding: $0) }
    }

    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 2, let data = FileManager.default.contents(atPath: args[0]),
              let scenes = try? JSONDecoder().decode(Scenes.self, from: data) else {
            FileHandle.standardError.write("usage: CairnYap --overlay-scenes <scenes.json> <out dir>\n".data(using: .utf8)!)
            return 2
        }
        let out = URL(fileURLWithPath: args[1])
        var code: Int32 = 0
        let done = DispatchSemaphore(value: 0)
        // Lean runs on its own thread with a large stack, as in the app.
        let t = Thread {
            defer { done.signal() }
            LeanRuntime.enter(module: runtime_initialize_cairn_Examples_Yap_Abi)
            do {
                let r = try Renderer()
                r.clearColor = Color(r: 0, g: 0, b: 0, a: 0)
                for s in scenes.states {
                    let (bytes, now) = scene(s)
                    let f = try frame(bytes)
                    guard let p = f.surfaces.first, p.shown else { throw CocoaError(.featureUnsupported) }
                    let canvas = Frame(size: p.canvas.size, draws: p.canvas.draws)
                    // The tape's own history, against the harness's.
                    var worst: Float = 0
                    for d in p.canvas.draws {
                        guard case let .paint(_, paint) = d, paint.shader == YapTape.name else { continue }
                        let a = paint.arrays, sc = paint.scalars
                        let nowMs = Double(Int64(now) - Int64(paint.origin))
                        let h = YapTape.history(now: nowMs, start: Double(sc[4]), stop: sc[5] < 0 ? nil : Double(sc[5]),
                                                times: a[0], levels: a[1])
                        worst = zip(h, s.levels).map { abs($0 - $1) }.max() ?? 0
                    }
                    let img = try r.image(canvas, scale: 2, time: UInt64(now) * 1_000_000)
                    try img.writePNG(to: out.appendingPathComponent(s.name + ".png"))
                    print("\(s.name): \(canvas.size.w)×\(canvas.size.h) pt, tape history vs harness: max \(worst)")
                }
            } catch {
                FileHandle.standardError.write("overlay scenes: \(error)\n".data(using: .utf8)!)
                code = 1
            }
        }
        t.stackSize = 64 << 20
        t.start()
        done.wait()
        return code
    }
}
