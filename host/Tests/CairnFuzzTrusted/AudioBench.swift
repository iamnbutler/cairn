import CairnFrame
import CairnHost
import Foundation

/// `CairnFuzzTrusted --bench-audio` (release): what the level stream and WAV extraction cost
/// the host, on synthetic audio (bench/effects.md, "Recording").
enum AudioBench {
    static func ms(_ ns: UInt64) -> String { String(format: "%.3f ms", Double(ns) / 1e6) }
    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    static func run() {
        var g = SplitMix(seed: 1)
        let minute = AudioSuite.signal(&g, 60 * 16000)

        // The level meter over a minute in ~43 ms buffers (2048 frames at 48 kHz, converted).
        var best = UInt64.max
        for _ in 0..<20 {
            var m = LevelMeter()
            var windows = 0
            let t0 = now()
            var i = 0
            while i < minute.count {
                let n = min(683, minute.count - i)
                minute[i..<i + n].withUnsafeBufferPointer { windows += m.feed($0).windows.count }
                i += n
            }
            best = min(best, now() - t0)
            precondition(windows == 3000)
        }
        print("level meter: 60 s of audio in \(ms(best)) (\(String(format: "%.1f", Double(best) / 60 / 1000)) µs per second of audio)")

        // Encoding the events Lean gets for a second (25 batches of two windows).
        let ev: [Event] = [.subEvent(id: 3, .audio(frames: 640, peak: 9000, windows: [Level(sumSq: 123456789, peak: 9000), Level(sumSq: 987654321, peak: 8000)]))]
        var bytes = 0
        let t1 = now()
        for _ in 0..<(25 * 1000) { bytes = encodeEvents(ev).count }
        print("event encode: \(bytes) bytes a batch, \(ms((now() - t1) / 1000)) per second of audio")

        // The whole path: a fake microphone delivering a minute as fast as it can through World
        // (append to the clip, hop to the queue, meter, send).
        let mic = FakeMic(buffers: stride(from: 0, to: minute.count, by: 683).map { Array(minute[$0..<min($0 + 683, minute.count)]) }, pauseUs: 0)
        var d = Devices.inert
        d.microphone = mic.microphone
        let world = World(handlers: Handlers(table: [:]), devices: d)
        let windows = Locked(0)
        world.send = { es in for case let .subEvent(_, .audio(_, _, ws)) in es { windows.update { $0 += ws.count } } }
        let t2 = now()
        world.run([], [.start(id: 1, .record(clip: 1))])
        _ = mic.waitDone(30)
        while windows.value < 3000 { usleep(100) }
        let tRec = now() - t2
        world.run([], [.stop(id: 1)])
        print("record through World: 60 s of audio in \(ms(tRec)) (\(String(format: "%.1f", Double(tRec) / 60 / 1000)) µs per second of audio)")

        // WAV extraction of the whole minute, and of a 10 s chunk from its middle.
        for (label, a, b) in [("60 s clip", UInt32(0), UInt32?.none), ("10 s chunk", UInt32(1000), UInt32?(1500))] {
            var best = UInt64.max
            var size = 0
            for _ in 0..<20 {
                let t = now()
                if case let .success(w) = world.clips.wav(1, start: a, stop: b, wait: 0) { size = w.count }
                best = min(best, now() - t)
            }
            print("wav \(label): \(size) bytes in \(ms(best))")
        }
        // And the upload body around it (Yap's multipart shape).
        var best2 = UInt64.max
        for _ in 0..<20 {
            let t = now()
            _ = Upload.body([.bytes(Array(repeating: 45, count: 200)), .wav(clip: 1, start: 0, stop: nil), .bytes(Array(repeating: 45, count: 40))], world.clips, wait: 0)
            best2 = min(best2, now() - t)
        }
        print("upload body with a 60 s wav part: \(ms(best2))")
    }
}
