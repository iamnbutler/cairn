import CairnFrame
import CairnRender
import Foundation
import Metal
import Testing

/// `make bench-render` (CAIRN_BENCH=1, release): CPU time to turn a frame into Metal commands
/// (instances, batches, atlas lookups, encoding, commit) and GPU time to execute them, for the
/// cases in bench/render.md. Skipped in normal test runs.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CAIRN_BENCH"] == "1"))
struct RenderBench {
    static func rects(_ n: Int) -> Frame {
        var d: [Draw] = [rect(R(0, 0, 1200, 800), rgb(0xf6f5f2))]
        for i in 0..<n {
            let x = Int32(i % 100) * 12, y = Int32(i / 100 % 66) * 12
            switch i % 3 {
            case 0: d.append(rect(R(x, y, 10, 10), rgb(0x3d7dd9)))
            case 1: d.append(rect(R(x, y, 10, 10), rgb(0xd94f3d), radius: 3))
            default: d.append(rect(R(x, y, 10, 10), white, radius: 2, border: Border(width: 1, color: rgb(0x999999))))
            }
        }
        return frame(1200, 800, d)
    }

    static func texts(_ n: Int, salt: String = "") -> Frame {
        var d: [Draw] = [rect(R(0, 0, 1200, 800), white)]
        for i in 0..<n {
            let x = Int32(i % 8) * 150, y = Int32(i / 8 % 50) * 16 + 13
            d.append(text(x, y, "Todo item \(i)\(salt)", font: Font(weight: i % 5 == 0 ? 700 : 400)))
        }
        return frame(1200, 800, d)
    }

    struct Result { var cpu: Double; var gpu: Double; var batches: Int }

    func measure(_ r: Renderer, _ tex: MTLTexture, reps: Int = 50, _ make: (Int) -> Frame) -> Result {
        var cpu: [Double] = [], gpu: [Double] = []
        var batches = 0
        for i in 0..<(reps + 5) {
            let f = make(i)
            let t0 = DispatchTime.now().uptimeNanoseconds
            let cmd = r.draw(frame: f, into: tex, scale: 2)
            let t1 = DispatchTime.now().uptimeNanoseconds
            cmd.waitUntilCompleted()
            if i >= 5 {
                cpu.append(Double(t1 - t0) / 1e6)
                gpu.append((cmd.gpuEndTime - cmd.gpuStartTime) * 1e3)
            }
            batches = r.lastStats.rectBatches + r.lastStats.glyphBatches
        }
        func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        return Result(cpu: median(cpu), gpu: median(gpu), batches: batches)
    }

    @Test func frames() throws {
        let r = try Renderer()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 2400, height: 1600, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let tex = r.device.makeTexture(descriptor: d)!
        let r1k = Self.rects(1000), r10k = Self.rects(10000), t1k = Self.texts(1000)
        let cases: [(String, (Int) -> Frame)] = [
            ("1,000 rects", { _ in r1k }),
            ("10,000 rects", { _ in r10k }),
            ("1,000 text runs, cached", { _ in t1k }),
            ("1,000 text runs, all new strings", { i in Self.texts(1000, salt: "·\(i)") }),
        ]
        print("render bench @2x into 2400x1600 bgra8Unorm, \(r.device.name), median of 50")
        for (name, make) in cases {
            let res = measure(r, tex, make)
            print(String(format: "  %-36@ CPU %.3f ms  GPU %.3f ms  (%d batches)", name as NSString, res.cpu, res.gpu, res.batches))
        }
    }
}
