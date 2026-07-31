import Foundation
import Darwin

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
}

private final class CommandOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let value = data
        lock.unlock()
        return value
    }
}

enum CommandRunner {
    static func runAsync(executable: String, arguments: [String], timeout: TimeInterval? = nil) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            try run(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    static func run(executable: String, arguments: [String], timeout: TimeInterval? = nil) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()

        let outputCapture = CommandOutputCapture()
        let errorCapture = CommandOutputCapture()
        let readers = DispatchGroup()

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outputCapture.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCapture.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let timedOut: Bool
        if let timeout {
            timedOut = completion.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                if completion.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = completion.wait(timeout: .now() + 2)
                }
                try? outputPipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
                _ = readers.wait(timeout: .now() + 1)
            }
        } else {
            completion.wait()
            timedOut = false
        }

        if !timedOut {
            readers.wait()
        }

        let output = String(decoding: outputCapture.snapshot(), as: UTF8.self)
        let error = String(decoding: errorCapture.snapshot(), as: UTF8.self)

        if timedOut {
            throw CommandRunnerError.timedOut(executable: executable, arguments: arguments, output: output, error: error)
        }

        return CommandResult(output: output, error: error, exitCode: process.terminationStatus)
    }
}

enum CommandRunnerError: LocalizedError {
    case timedOut(executable: String, arguments: [String], output: String, error: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let executable, let arguments, _, _):
            let joined = ([executable] + arguments).joined(separator: " ")
            return "Command timed out: \(joined)"
        }
    }
}
