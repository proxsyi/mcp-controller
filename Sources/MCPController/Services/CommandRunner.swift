import Foundation
import Darwin

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
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

        var outputData = Data()
        var errorData = Data()
        let outputLock = NSLock()
        let errorLock = NSLock()
        let readers = DispatchGroup()

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            outputData = data
            outputLock.unlock()
            readers.leave()
        }

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorLock.lock()
            errorData = data
            errorLock.unlock()
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

        outputLock.lock()
        let capturedOutput = outputData
        outputLock.unlock()
        errorLock.lock()
        let capturedError = errorData
        errorLock.unlock()
        let output = String(decoding: capturedOutput, as: UTF8.self)
        let error = String(decoding: capturedError, as: UTF8.self)

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
