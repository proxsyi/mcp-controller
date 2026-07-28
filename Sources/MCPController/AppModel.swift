import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [ServerProfile] = []
    @Published var selectedID: UUID?
    @Published private(set) var phases: [UUID: RuntimePhase] = [:]
    @Published private(set) var logs: [UUID: String] = [:]
    @Published private(set) var gatewayLeases: [UUID: GatewayLeaseSnapshot] = [:]
    @Published private(set) var pendingConnections: [UUID: [GatewayPendingSnapshot]] = [:]
    @Published var presentedError: String?

    private let store = ProfileStore()
    private let gatewayManager = ExclusiveGatewayManager()
    private var processes: [UUID: Process] = [:]
    private var outputPipes: [UUID: [Pipe]] = [:]
    private var userStoppedProfiles: Set<UUID> = []

    var runningCount: Int {
        phases.values.filter(\.isActive).count
    }

    init() {
        gatewayManager.onStateChange = { [weak self] profileID, active, pending in
            Task { @MainActor in
                if let active { self?.gatewayLeases[profileID] = active }
                else { self?.gatewayLeases.removeValue(forKey: profileID) }
                self?.pendingConnections[profileID] = pending
            }
        }
        gatewayManager.onLog = { [weak self] profileID, message in
            Task { @MainActor in self?.appendLog(profileID, message) }
        }
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

    func lease(for id: UUID) -> GatewayLeaseSnapshot? {
        gatewayLeases[id]
    }

    func waiting(for id: UUID) -> [GatewayPendingSnapshot] {
        pendingConnections[id] ?? []
    }

    func approve(profileID: UUID, clientID: String) {
        gatewayManager.approve(profileID: profileID, clientID: clientID)
    }

    func deny(profileID: UUID, clientID: String) {
        gatewayManager.deny(profileID: profileID, clientID: clientID)
    }

    func releaseLease(profileID: UUID) {
        gatewayManager.release(profileID: profileID)
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
        copy.clientCredentials = copy.clientCredentials.map { GatewayClientCredential.generate(name: $0.name) }
        add(copy)
    }

    func remove(_ profile: ServerProfile) {
        stop(profile) { [weak self] in
            guard let self else { return }
            self.profiles.removeAll { $0.id == profile.id }
            self.phases.removeValue(forKey: profile.id)
            self.logs.removeValue(forKey: profile.id)
            self.gatewayLeases.removeValue(forKey: profile.id)
            self.pendingConnections.removeValue(forKey: profile.id)
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

        userStoppedProfiles.remove(profile.id)
        phases[profile.id] = .starting
        appendLog(profile.id, "Starting \(profile.name)…\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: profile.executablePath)
        process.arguments = profile.arguments.map { $0.replacingOccurrences(of: "{port}", with: String(profile.localPort)) }
        if !profile.workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: profile.workingDirectory, isDirectory: true)
        }
        process.environment = launchEnvironment(for: profile)

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        output.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        error.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.gatewayManager.stop(profileID: profile.id)
                self.processes.removeValue(forKey: profile.id)
                self.outputPipes.removeValue(forKey: profile.id)

                let wasUserStop = self.userStoppedProfiles.remove(profile.id) != nil
                if wasUserStop || self.phase(for: profile.id) == .stopping || self.phase(for: profile.id) == .stopped {
                    self.phases[profile.id] = .stopped
                    self.appendLog(profile.id, "Process stopped.\n")
                } else {
                    self.phases[profile.id] = process.terminationStatus == 0 ? .stopped : .failed("Exited with code \(process.terminationStatus)")
                    self.appendLog(profile.id, "Process exited with code \(process.terminationStatus).\n")
                }
            }
        }

        do {
            try process.run()
            processes[profile.id] = process
            outputPipes[profile.id] = [output, error]
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(profile.startupDelaySeconds))
                self.finishStart(profile)
            }
        } catch {
            phases[profile.id] = .failed(error.localizedDescription)
            presentedError = "Could not start \(profile.name): \(error.localizedDescription)"
        }
    }

    private func finishStart(_ profile: ServerProfile) {
        guard processes[profile.id]?.isRunning == true else { return }
        do {
            try gatewayManager.start(profile: profile)
            try enableExposure(profile)
            phases[profile.id] = .running
            appendLog(profile.id, exposureMessage(for: profile))
        } catch {
            gatewayManager.stop(profileID: profile.id)
            processes[profile.id]?.terminate()
            phases[profile.id] = .failed(error.localizedDescription)
            presentedError = "\(profile.name) started, but its gateway or exposure failed and the process was stopped: \(error.localizedDescription)"
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

        userStoppedProfiles.insert(profile.id)
        gatewayManager.stop(profileID: profile.id)
        if let process = processes[profile.id], process.isRunning {
            process.terminate()
        }
        processes.removeValue(forKey: profile.id)
        outputPipes.removeValue(forKey: profile.id)
        phases[profile.id] = .stopped
        appendLog(profile.id, "Stopped, released the AI lease, and removed the owned Tailscale route.\n")
        completion?()
    }

    func stopAll() {
        let active = profiles.filter { phase(for: $0.id).isActive }
        for profile in active { stop(profile) }
    }

    func clearLog(for id: UUID) {
        logs[id] = ""
    }

    private func launchEnvironment(for profile: ServerProfile) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging(profile.environment) { _, configured in configured }
        let standardPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (standardPaths + existingPaths)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
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
        let gate = profile.exclusiveGatewayEnabled ? " through its exclusive AI gateway" : ""
        return switch profile.exposureMode {
        case .disabled: "Running locally\(gate) on port \(profile.exposedLocalPort).\n"
        case .tailnet: "Running\(gate) and exposed to the tailnet at \(profile.normalizedMountPath).\n"
        case .funnel: "Running\(gate) and publicly exposed through Funnel at \(profile.normalizedMountPath).\n"
        }
    }

    private func logHandler(for id: UUID) -> @Sendable (FileHandle) -> Void {
        { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendLog(id, text)
            }
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
