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

    @Test func requestsAnswerOnceUnderTheirIds() {
        let inbox = Inbox()
        // A handler that tries to answer twice: only the first answer is sent.
        let world = World(handlers: Handlers(table: [0: { _, reply in reply(.bytes([1])); reply(.done) }]))
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
        let world = World()
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
        let world = World(handlers: Handlers(table: [0: { _, reply in gate.wait(); reply(.done) }]))
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
