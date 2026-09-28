import Darwin
import Dispatch
import Foundation
import Testing
@testable import StatsCore

private final class FixtureResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BoundedProcessResult?

    func set(_ result: BoundedProcessResult) {
        lock.lock(); stored = result; lock.unlock()
    }

    func get() -> BoundedProcessResult? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private struct FixtureOutcome {
    var result: BoundedProcessResult
    var elapsed: TimeInterval
    var pid: pid_t?
}

private func runFixture(
    _ body: String,
    timeout: TimeInterval = 0.5,
    maxOutputBytes: Int = 64 * 1024,
    terminationGrace: TimeInterval = 0.05,
    cleanProcessGroup: Bool = false
) -> FixtureOutcome? {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zstats-process-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pidURL = directory.appendingPathComponent("pid")
    let script = "printf '%s' \"$$\" > '\(pidURL.path)'; \(body)"
    let runner = BoundedProcessRunner(maxOutputBytes: maxOutputBytes, terminationGrace: terminationGrace)
    let resultBox = FixtureResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    let start = ProcessInfo.processInfo.systemUptime
    DispatchQueue.global(qos: .userInitiated).async {
        resultBox.set(runner.run(executable: "/bin/sh", arguments: ["-c", script], timeout: timeout))
        semaphore.signal()
    }

    let outerLimit = timeout + terminationGrace + 2
    if semaphore.wait(timeout: .now() + outerLimit) == .timedOut {
        if let pid = fixturePID(at: pidURL) { _ = Darwin.kill(-pid, SIGKILL) }
        _ = semaphore.wait(timeout: .now() + 1)
        try? FileManager.default.removeItem(at: directory)
        return nil
    }

    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let pid = fixturePID(at: pidURL)
    if cleanProcessGroup, let pid { _ = Darwin.kill(-pid, SIGKILL) }
    try? FileManager.default.removeItem(at: directory)
    guard let result = resultBox.get() else { return nil }
    return FixtureOutcome(result: result, elapsed: elapsed, pid: pid)
}

private func fixturePID(at url: URL) -> pid_t? {
    guard let value = try? String(contentsOf: url, encoding: .utf8), let pid = pid_t(value), pid > 1 else { return nil }
    return pid
}

private func isReaped(_ pid: pid_t?) -> Bool {
    guard let pid else { return false }
    errno = 0
    return Darwin.kill(pid, 0) == -1 && errno == ESRCH
}

@Test func runnerReturnsNormalOutputAndNonzeroExitSeparately() throws {
    let success = try #require(runFixture("printf 'hello'"))
    #expect(success.result == .success(Data("hello".utf8)))

    let nonzero = try #require(runFixture("printf 'failed'; exit 7"))
    #expect(nonzero.result == .nonzeroExit(status: 7, output: Data("failed".utf8)))
}

@Test func timeoutRejectsPartialOutputAndReapsTermIgnoringChild() throws {
    let outcome = try #require(runFixture("trap '' TERM; printf 'partial'; while :; do sleep 1; done", timeout: 0.08))
    #expect(outcome.result == .timedOut)
    #expect(outcome.elapsed < 1)
    #expect(isReaped(outcome.pid))
}

@Test func slowOutputTimesOutWithoutReturningPartialData() throws {
    let outcome = try #require(runFixture("printf 'partial'; sleep 5; printf 'late'", timeout: 0.08))
    #expect(outcome.result == .timedOut)
    #expect(outcome.elapsed < 1)
}

@Test func stdoutEOFDoesNotFinishBeforeOwnedChildExits() throws {
    let outcome = try #require(runFixture("exec 1>&-; sleep 0.15; exit 0", timeout: 1))
    #expect(outcome.result == .success(Data()))
    #expect(outcome.elapsed >= 0.1)
    #expect(outcome.elapsed < 0.8)
}

@Test func childExitDoesNotWaitForDescendantHoldingStdout() throws {
    let outcome = try #require(runFixture("(sleep 5) & printf 'done'; exit 0", timeout: 1, cleanProcessGroup: true))
    #expect(outcome.result == .success(Data("done".utf8)))
    #expect(outcome.elapsed < 0.8)
    #expect(isReaped(outcome.pid))
}

@Test func oversizedOutputIsRejectedAtConfiguredCap() throws {
    let outcome = try #require(runFixture("exec /usr/bin/yes x", timeout: 1, maxOutputBytes: 1_024))
    #expect(outcome.result == .outputLimitExceeded)
    #expect(outcome.elapsed < 1)
}

@Test func runnerRecoversForASubsequentInvocationAfterTimeout() throws {
    let timedOut = try #require(runFixture("sleep 5", timeout: 0.05))
    #expect(timedOut.result == .timedOut)
    let success = try #require(runFixture("printf 'recovered'"))
    #expect(success.result == .success(Data("recovered".utf8)))
}

@Test func spawnFailureIsDistinctFromChildExit() {
    let result = BoundedProcessRunner().run(executable: "/path/that/does/not/exist", arguments: [], timeout: 0.1)
    guard case .failure(.spawn(let code)) = result else {
        Issue.record("Expected a spawn failure, got \(result)")
        return
    }
    #expect(code == ENOENT)
}
