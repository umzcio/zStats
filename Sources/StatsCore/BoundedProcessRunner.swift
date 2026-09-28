import Darwin
import Dispatch
import Foundation

public enum BoundedProcessFailure: Equatable, Sendable {
    case invalidExecutable
    case invalidOutputLimit
    case invalidTimeout
    case pipe(Int32)
    case fileDescriptor(Int32)
    case spawnSetup(Int32)
    case spawn(Int32)
    case read(Int32)
    case poll(Int32)
    case wait(Int32)
}

public enum BoundedProcessResult: Equatable, Sendable {
    case success(Data)
    case nonzeroExit(status: Int32, output: Data)
    case timedOut
    case outputLimitExceeded
    case failure(BoundedProcessFailure)
}

public struct BoundedProcessRunner: Sendable {
    public let maxOutputBytes: Int
    public let terminationGrace: TimeInterval

    public init(maxOutputBytes: Int = 1_048_576, terminationGrace: TimeInterval = 0.1) {
        self.maxOutputBytes = maxOutputBytes
        self.terminationGrace = max(0, terminationGrace)
    }

    public func run(executable: String, arguments: [String], timeout: TimeInterval) -> BoundedProcessResult {
        guard executable.hasPrefix("/") else { return .failure(.invalidExecutable) }
        guard maxOutputBytes >= 0 else { return .failure(.invalidOutputLimit) }
        guard timeout.isFinite, timeout >= 0 else { return .failure(.invalidTimeout) }

        var descriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&descriptors) == 0 else { return .failure(.pipe(errno)) }
        var readDescriptor = descriptors[0]
        var writeDescriptor = descriptors[1]
        defer {
            if readDescriptor >= 0 { Darwin.close(readDescriptor) }
            if writeDescriptor >= 0 { Darwin.close(writeDescriptor) }
        }

        guard setFlag(FD_CLOEXEC, using: F_SETFD, on: readDescriptor),
              setFlag(FD_CLOEXEC, using: F_SETFD, on: writeDescriptor),
              setFlag(O_NONBLOCK, using: F_SETFL, on: readDescriptor) else {
            return .failure(.fileDescriptor(errno))
        }

        var actions: posix_spawn_file_actions_t?
        var setupError = posix_spawn_file_actions_init(&actions)
        guard setupError == 0 else { return .failure(.spawnSetup(setupError)) }
        defer { posix_spawn_file_actions_destroy(&actions) }

        setupError = posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDOUT_FILENO)
        if setupError == 0 { setupError = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) }
        if setupError == 0 { setupError = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) }
        if setupError == 0 { setupError = posix_spawn_file_actions_addclose(&actions, readDescriptor) }
        if setupError == 0 { setupError = posix_spawn_file_actions_addclose(&actions, writeDescriptor) }
        guard setupError == 0 else { return .failure(.spawnSetup(setupError)) }

        var attributes: posix_spawnattr_t?
        setupError = posix_spawnattr_init(&attributes)
        guard setupError == 0 else { return .failure(.spawnSetup(setupError)) }
        defer { posix_spawnattr_destroy(&attributes) }
        setupError = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        if setupError == 0 { setupError = posix_spawnattr_setpgroup(&attributes, 0) }
        guard setupError == 0 else { return .failure(.spawnSetup(setupError)) }

        let strings = ([executable] + arguments).map { strdup($0) }
        guard strings.allSatisfy({ $0 != nil }), let executableString = strings[0] else {
            for string in strings { free(string) }
            return .failure(.spawn(ENOMEM))
        }
        defer { for string in strings { free(string) } }
        var argv = strings + [nil]
        let environmentStrings = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        guard environmentStrings.allSatisfy({ $0 != nil }) else {
            for string in environmentStrings { free(string) }
            return .failure(.spawn(ENOMEM))
        }
        defer { for string in environmentStrings { free(string) } }
        var environment = environmentStrings + [nil]
        var child: pid_t = 0
        let spawnError = posix_spawn(&child, executableString, &actions, &attributes, &argv, &environment)
        guard spawnError == 0 else { return .failure(.spawn(spawnError)) }

        Darwin.close(writeDescriptor)
        writeDescriptor = -1

        var output = Data()
        output.reserveCapacity(min(maxOutputBytes, 65_536))
        var outputExceeded = false
        var pipeOpen = true
        var childStatus: Int32?
        var readTimedOut = false
        let deadline = monotonicTime() + timeout

        while true {
            if let failure = drain(
                descriptor: &readDescriptor,
                pipeOpen: &pipeOpen,
                output: &output,
                exceeded: &outputExceeded,
                timedOut: &readTimedOut,
                deadline: deadline
            ) {
                terminateAndReap(child)
                return .failure(failure)
            }
            if readTimedOut {
                terminateAndReap(child)
                return .timedOut
            }
            if let failure = reap(child, status: &childStatus) {
                terminateAndReap(child)
                return .failure(failure)
            }
            if outputExceeded {
                terminateAndReap(child)
                return .outputLimitExceeded
            }
            if let childStatus {
                // Any bytes written before child exit are already available to this final nonblocking drain.
                if let failure = drain(
                    descriptor: &readDescriptor,
                    pipeOpen: &pipeOpen,
                    output: &output,
                    exceeded: &outputExceeded,
                    timedOut: &readTimedOut,
                    deadline: deadline
                ) { return .failure(failure) }
                if readTimedOut { return .timedOut }
                if outputExceeded { return .outputLimitExceeded }
                let status = exitStatus(childStatus)
                return status == 0 ? .success(output) : .nonzeroExit(status: status, output: output)
            }

            let remaining = deadline - monotonicTime()
            if remaining <= 0 {
                terminateAndReap(child)
                return .timedOut
            }

            var descriptor = pollfd(fd: pipeOpen ? readDescriptor : -1, events: Int16(POLLIN | POLLHUP), revents: 0)
            let milliseconds = Int32(max(1, min(10, ceil(remaining * 1_000))))
            let pollResult = Darwin.poll(&descriptor, 1, milliseconds)
            if pollResult < 0, errno != EINTR {
                let code = errno
                terminateAndReap(child)
                return .failure(.poll(code))
            }
        }
    }

    private func setFlag(_ flag: Int32, using command: Int32, on descriptor: Int32) -> Bool {
        let getCommand = command == F_SETFL ? F_GETFL : F_GETFD
        let current = fcntl(descriptor, getCommand)
        return current >= 0 && fcntl(descriptor, command, current | flag) == 0
    }

    private func drain(
        descriptor: inout Int32,
        pipeOpen: inout Bool,
        output: inout Data,
        exceeded: inout Bool,
        timedOut: inout Bool,
        deadline: TimeInterval
    ) -> BoundedProcessFailure? {
        guard pipeOpen else { return nil }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            if monotonicTime() >= deadline { timedOut = true; return nil }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let available = max(0, maxOutputBytes - output.count)
                let accepted = min(Int(count), available)
                if accepted > 0 { output.append(contentsOf: buffer.prefix(accepted)) }
                if Int(count) > accepted { exceeded = true; return nil }
            } else if count == 0 {
                Darwin.close(descriptor)
                descriptor = -1
                pipeOpen = false
                return nil
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return nil
            } else {
                return .read(errno)
            }
        }
    }

    private func reap(_ child: pid_t, status: inout Int32?) -> BoundedProcessFailure? {
        guard status == nil else { return nil }
        while true {
            var rawStatus: Int32 = 0
            let result = Darwin.waitpid(child, &rawStatus, WNOHANG)
            if result == child { status = rawStatus; return nil }
            if result == 0 { return nil }
            if errno == EINTR { continue }
            return .wait(errno)
        }
    }

    private func terminateAndReap(_ child: pid_t) {
        var status: Int32?
        if reap(child, status: &status) != nil || status != nil { return }

        _ = Darwin.kill(-child, SIGTERM)
        _ = Darwin.kill(child, SIGTERM)
        let termDeadline = monotonicTime() + terminationGrace
        while monotonicTime() < termDeadline {
            if reap(child, status: &status) != nil || status != nil { return }
            usleep(2_000)
        }

        _ = Darwin.kill(-child, SIGKILL)
        _ = Darwin.kill(child, SIGKILL)
        let killDeadline = monotonicTime() + min(terminationGrace, 0.05)
        while monotonicTime() < killDeadline {
            if reap(child, status: &status) != nil || status != nil { return }
            usleep(2_000)
        }

        DispatchQueue.global(qos: .utility).async {
            var rawStatus: Int32 = 0
            while Darwin.waitpid(child, &rawStatus, 0) < 0, errno == EINTR {}
        }
    }

    private func exitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private func monotonicTime() -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
