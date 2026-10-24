import CairnFrame
import Foundation
import Testing
@testable import CairnHost

/// Collects what the world sends, from any thread.
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []
    func add(_ es: [Event]) { lock.lock(); events += es; lock.unlock() }
    var all: [Event] { lock.lock(); defer { lock.unlock() }; return events }

    func wait(for n: Int, timeout: Double = 3) -> [Event] {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while all.count < n && Date() < deadline { usleep(500) }
        return all
    }
}

@Suite struct WorldTests {
    static func scratch() -> String {
        NSTemporaryDirectory() + "cairn-world-\(UUID().uuidString)"
    }

    @Test func filesRoundTrip() throws {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/a/b/c.bin"
        #expect(Files.read(path) == .failed(.notFound, Files.read(path).message))
        #expect(Files.write(path, [0, 1, 255]) == .done)  // creates a/b
        #expect(Files.read(path) == .bytes([0, 1, 255]))
        #expect(Files.write(path, []) == .done)  // replaces
        #expect(Files.read(path) == .bytes([]))
        if case .failed(.invalid, _) = Files.read("") {} else { Issue.record("empty path") }
        if case .failed = Files.read(dir) {} else { Issue.record("reading a directory") }
        #expect(Files.expand("~/x") == NSHomeDirectory() + "/x")
        #expect(Files.expand("/tmp/~/x") == "/tmp/~/x")
    }

    @Test func dayFiles() {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let day = dir + "/transcripts/2026-10-23.jsonl"
        #expect(Files.append(day, Array("a\n".utf8)) == .done)  // creates transcripts/
        #expect(Files.append(day, Array("b\n".utf8)) == .done)
        #expect(Files.read(day) == .bytes(Array("a\nb\n".utf8)))
        #expect(Files.append(dir + "/transcripts/2026-10-22.jsonl", []) == .done)
        #expect(Files.list(dir + "/transcripts") == .names(["2026-10-22.jsonl", "2026-10-23.jsonl"]))
        #expect(Files.delete(dir + "/transcripts/2026-10-22.jsonl") == .done)
        #expect(Files.list(dir + "/transcripts") == .names(["2026-10-23.jsonl"]))
        if case .failed(.notFound, _) = Files.delete(dir + "/transcripts/2026-10-22.jsonl") {} else { Issue.record("delete twice") }
        if case .failed(.invalid, _) = Files.delete(dir + "/transcripts") {} else { Issue.record("delete a directory") }
        if case .failed(.notFound, _) = Files.list(dir + "/nothing") {} else { Issue.record("list missing") }
    }

    /// `listDir` gives the bytes the file system holds, sorted by UTF-8 bytes, including a
    /// leading U+FEFF, which `FileManager.contentsOfDirectory(atPath:)` drops (found by
    /// `effects.list-dir` at 20,000 cases; the oracle was wrong, not `Files.list`).
    @Test func listDirKeepsALeadingBOM() {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for n in ["a", "\u{FEFF}a", "\u{FEFF}", "Z"] { #expect(Files.write(dir + "/" + n, [1]) == .done) }
        #expect(Files.list(dir) == .names(["Z", "a", "\u{FEFF}", "\u{FEFF}a"]))
        #expect(Files.read(dir + "/\u{FEFF}a") == .bytes([1]))
    }

    @Test func watchFileSeesChanges() {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/config.json"
        let inbox = Inbox()
        let world = World(devices: .inert)
        world.watchPeriodMs = 5
        world.send = { inbox.add($0) }
        world.run([], [.start(id: 4, .watchFile(path: path))])
        usleep(30_000)
        #expect(inbox.all.isEmpty)
        _ = Files.write(path, Array("{}".utf8))
        #expect(inbox.wait(for: 1) == [.subEvent(id: 4, .changed)])
        world.run([], [.stop(id: 4)])
        let n = inbox.all.count
        _ = Files.write(path, Array("{ }".utf8))
        usleep(30_000)
        #expect(inbox.all.count == n)
        #expect(world.running.isEmpty)
    }

    @Test func requestsAnswerOnceUnderTheirIds() {
        let inbox = Inbox()
        // A handler that tries to answer twice: only the first answer is sent.
        let world = World(handlers: Handlers(table: [0: { _, reply in reply(.bytes([1])); reply(.done) }]), devices: .inert)
        world.send = { inbox.add($0) }
        world.run([.request(id: 7, .readFile(path: "x")), .beep, .request(id: 9, .playSound(name: "y"))], [])
        let got = inbox.wait(for: 2)
        usleep(20_000)
        #expect(inbox.all.count == 2)
        #expect(got.contains(.reply(id: 7, .bytes([1]))))
        // No handler for kind 2 here: an ordinary failure, still under the request's id.
        #expect(got.contains { if case .reply(9, .failed(.invalid, _)) = $0 { true } else { false } })
    }

    @Test func subscriptionsTickUntilStopped() {
        let inbox = Inbox()
        let world = World(devices: .inert)
        world.send = { inbox.add($0) }
        world.run([], [.start(id: 3, .every(ms: 10))])
        #expect(world.running == [3])
        let ticks = inbox.wait(for: 3)
        #expect(ticks.prefix(3).allSatisfy { $0 == .subEvent(id: 3, .tick) })
        world.run([], [.stop(id: 3)])
        #expect(world.running.isEmpty)
        let n = inbox.all.count
        usleep(60_000)
        #expect(inbox.all.count == n)
    }

    @Test func resetStopsEverythingAndDropsLateReplies() {
        let inbox = Inbox()
        let gate = DispatchSemaphore(value: 0)
        let world = World(handlers: Handlers(table: [0: { _, reply in gate.wait(); reply(.done) }]), devices: .inert)
        world.send = { inbox.add($0) }
        world.run([.request(id: 1, .readFile(path: "x"))], [.start(id: 1, .every(ms: 1000))])
        world.reset()
        #expect(world.running.isEmpty)
        gate.signal()
        usleep(50_000)
        #expect(inbox.all.isEmpty)
    }
}

extension Reply {
    var message: String { if case let .failed(_, m) = self { m } else { "" } }
}
