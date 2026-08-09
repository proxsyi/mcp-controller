import Foundation

@MainActor
final class AutoReleaseAllLoop {
    static let shellPath = "/bin/zsh"
    static let command = "while true; do ~/.local/bin/mcpctl release-all; sleep 60; done"

    var onTermination: (() -> Void)?
    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    func start() throws {
        guard process == nil else { return }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: Self.shellPath)
        newProcess.arguments = ["-lc", Self.command]
        newProcess.terminationHandler = { [weak self, weak newProcess] _ in
            Task { @MainActor in
                guard let self, let newProcess, self.process === newProcess else { return }
                self.process = nil
                self.onTermination?()
            }
        }

        try newProcess.run()
        process = newProcess
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        if process.isRunning {
            process.terminate()
        }
    }
}
