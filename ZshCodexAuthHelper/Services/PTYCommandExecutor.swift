import Darwin
import Foundation

enum PTYCommandError: LocalizedError {
    case couldNotOpenPTY

    var errorDescription: String? {
        switch self {
        case .couldNotOpenPTY:
            return "Could not open a terminal session."
        }
    }
}

struct PTYCommandResult: Equatable {
    let output: String
    let exitCode: Int32
}

final class RunningPTYCommand {
    private let process: Process
    private let masterFD: Int32
    private let lock = NSLock()
    private var isClosed = false

    init(process: Process, masterFD: Int32) {
        self.process = process
        self.masterFD = masterFD
    }

    var isRunning: Bool {
        process.isRunning
    }

    func sendInput(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }

        lock.lock()
        let canWrite = isClosed == false
        lock.unlock()

        guard canWrite else {
            return
        }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            _ = Darwin.write(masterFD, baseAddress, data.count)
        }
    }

    func terminate() {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if self.process.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    fileprivate func markClosed() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }
}

final class PTYCommandExecutor {
    init() {}

    @discardableResult
    func start(
        _ command: CommandDefinition,
        onOutput: @escaping (String) -> Void,
        onTermination: @escaping (PTYCommandResult) -> Void
    ) throws -> RunningPTYCommand {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw PTYCommandError.couldNotOpenPTY
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = mergedEnvironment(overrides: command.environment)

        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let runningCommand = RunningPTYCommand(process: process, masterFD: masterFD)

        do {
            try process.run()
            try? slaveHandle.close()
        } catch {
            try? slaveHandle.close()
            Darwin.close(masterFD)
            throw error
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let output = self.readOutput(from: masterFD, onOutput: onOutput)
            process.waitUntilExit()
            runningCommand.markClosed()
            Darwin.close(masterFD)
            onTermination(PTYCommandResult(output: output, exitCode: process.terminationStatus))
        }

        return runningCommand
    }

    func runForTesting(
        _ command: CommandDefinition,
        input: String? = nil,
        stopAfterInput: Bool = false,
        timeout: TimeInterval = 5
    ) async throws -> PTYCommandResult {
        let completion = CompletionBox()

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let runningCommand = try start(
                    command,
                    onOutput: { _ in },
                    onTermination: { result in
                        completion.resume(continuation, with: .success(result))
                    }
                )

                if let input {
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                        runningCommand.sendInput(input)
                        if stopAfterInput {
                            runningCommand.sendInput("\u{04}")
                        }
                    }
                }

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    if runningCommand.isRunning {
                        runningCommand.terminate()
                    }
                }
            } catch {
                completion.resume(continuation, with: .failure(error))
            }
        }
    }

    private func readOutput(from fileDescriptor: Int32, onOutput: @escaping (String) -> Void) -> String {
        var collected = ""
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let count = Darwin.read(fileDescriptor, buffer, bufferSize)
            if count > 0 {
                let data = Data(bytes: buffer, count: count)
                let string = String(decoding: data, as: UTF8.self)
                collected += string
                onOutput(string)
            } else {
                break
            }
        }

        return collected
    }

    private func mergedEnvironment(overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides {
            environment[key] = value
        }
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["LC_ALL"] = environment["LC_ALL"] ?? "en_US.UTF-8"
        return environment
    }
}

private final class CompletionBox {
    private let lock = NSLock()
    private var didResume = false

    func resume<T>(
        _ continuation: CheckedContinuation<T, any Error>,
        with result: Result<T, any Error>
    ) {
        lock.lock()
        guard didResume == false else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

