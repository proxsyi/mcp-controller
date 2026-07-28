import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [ServerProfile] = []
    @Published var selectedID: UUID?
    @Published private(set) var phases: [UUID: RuntimePhase] = [:]
    @Published private(set) var logs: [UUID: String] = [:]
    @Published var presentedError: String?

    private let store = ProfileStore()
    private var processes: [UUID: Process] = [:]
    private var outputPipes: [UUID: [Pipe]] = [:]

    var runningCount: Int {
        phases.values.filter(\.isActive).count
    }

    init() {
        do {
            profiles = try store.load()
            selectedID = profiles.first?.id
            for profile in profiles where profile.autoStart {
                start(profile)
            }
        } catch {
            presentedError = "Could not load server profiles: \(error.localizedDescription)"
        }
    }

    func phase(for id: UUID) -> RuntimePhase {
        phases[id] ?? .stopped
    }

    func add(_ profile: ServerProfile) {
        profiles.append(profile)
        selectedID = profile.id
        persist()
    }

    func update(_ profile: ServerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func duplicate(_ profile: ServerProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name += " Copy"
        copy.autoStart = false
        add(copy)
    }

    func remove(_ profile: ServerProfile) {
        stop(profile) { [weak self] in
            guard let self else { return }
            self.profiles.removeAll { $0.id == profile.id }
            self.phases.removeValue(forKey: profile.id)
            self.logs.removeValue(forKey: profile.id)
            self.selectedID = self.profiles.first?.id
            self.persist()
        }
    }

    func start(_ profile: ServerProfile) {
        guard !phase(for: profile.id).isActive else { return }
        let errors = profile.validationErrors()
        guard errors.isEmpty else {
            phases[profile.id] = .failed(errors.joined(separator: " "))
            presentedError = errors.joined(separator: "\n")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: profile.executablePath) else {
            let message = "The executable does not exist or is not executable: \(profile.executablePath)"
            phases[profile.id] = .failed(message)
            presentedError = message
            return
        }

        phases[profile.id] = .starting
        appendLog(profile.id, "Starting \(profile.name)…\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: profile.executablePath)
        process.arguments = profile.arguments.map { $0.replacingOccurrences(of: "{port}", with: String(profile.localPort)) }
        if !profile.workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: profile.workingDirectory, isDirectory: true)
        }
        process.environment = ProcessInfo.processInfo.environment.merging(profile.environment) { _, configured in configured }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        output.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        error.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.processes.removeValue(forKey: profile.id)
                self.outputPipes.removeValue(forKey: profile.id)
                if self.phase(for: profile.id) != .stopping {
                    self.phases[profile.id] = process.terminationStatus == 0 ? .stopped : .failed("Exited with code \(process.terminationStatus)")
                }
                self.appendLog(profile.id, "Process exited with code \(process.terminationStatus).\n")
            }
        }

        do {
            try process.run()
            processes[profile.id] = process
            outputPipes[profile.id] = [output, error]
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(profile.startupDelaySeconds))
                await self.finishStart(profile)
            }
        } catch {
            phases[profile.id] = .failed(error.localizedDescription)
            presentedError = "Could not start \(profile.name): \(error.localizedDescription)"
        }
    }

    private func finishStart(_ profile: ServerProfile) {
        guard processes[profile.id]?.isRunning == true else { return }
        do {
            try enableExposure(profile)
            phases[profile.id] = .running
            appendLog(profile.id, exposureMessage(for: profile))
        } catch {
            processes[profile.id]?.terminate()
            phases[profile.id] = .failed(error.localizedDescription)
            presentedError = "\(profile.name) started, but exposure failed and the process was stopped: \(error.localizedDescription)"
        }
    }

    func stop(_ profile: ServerProfile, completion: (() -> Void)? = nil) {
        phases[profile.id] = .stopping
        do {
            try disableExposure(profile)
        } catch {
            presentedError = "Could not remove exposure for \(profile.name): \(error.localizedDescription)"
            phases[profile.id] = .failed(error.localizedDescription)
            return
        }

        if let process = processes[profile.id], process.isRunning {
            process.terminate()
        }
        processes.removeValue(forKey: profile.id)
        outputPipes.removeValue(forKey: profile.id)
        phases[profile.id] = .stopped
        appendLog(profile.id, "Stopped and removed owned Tailscale route.\n")
        completion?()
    }

    func stopAll() {
        let active = profiles.filter { phase(for: $0.id).isActive }
        for profile in active { stop(profile) }
    }

    func clearLog(for id: UUID) {
        logs[id] = ""
    }

    private func enableExposure(_ profile: ServerProfile) throws {
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: profile) else { return }
        let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
        guard result.exitCode == 0 else {
            throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
    }

    private func disableExposure(_ profile: ServerProfile) throws {
        guard let arguments = TailscaleCommandBuilder.disableArguments(for: profile) else { return }
        let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
        guard result.exitCode == 0 else {
            throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
    }

    private func exposureMessage(for profile: ServerProfile) -> String {
        switch profile.exposureMode {
        case .disabled: "Running locally on port \(profile.localPort).\n"
        case .tailnet: "Running and exposed to the tailnet at \(profile.normalizedMountPath).\n"
        case .funnel: "Running and publicly exposed through Funnel at \(profile.normalizedMountPath).\n"
        }
    }

    private func logHandler(for id: UUID) -> (FileHandle) -> Void {
        { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.appendLog(id, text) }
        }
    }

    private func appendLog(_ id: UUID, _ text: String) {
        let combined = (logs[id] ?? "") + text
        logs[id] = String(combined.suffix(100_000))
    }

    private func persist() {
        do {
            try store.save(profiles)
        } catch {
            presentedError = "Could not save server profiles: \(error.localizedDescription)"
        }
    }
}

enum ControllerError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
