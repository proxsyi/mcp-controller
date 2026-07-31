import Foundation
import Darwin

@MainActor
final class AppModel: ObservableObject {
    static var shared: AppModel?

    @Published var profiles: [ServerProfile] = []
    @Published var selectedID: UUID?
    @Published private(set) var phases: [UUID: RuntimePhase] = [:]
    @Published private(set) var logs: [UUID: String] = [:]
    @Published private(set) var gatewayLeases: [UUID: GatewayLeaseSnapshot] = [:]
    @Published private(set) var pendingConnections: [UUID: [GatewayPendingSnapshot]] = [:]
    @Published var tailscaleFunnelRunning = UserDefaults.standard.bool(forKey: "tailscale.funnelRunning")
    @Published var presentedError: String?
    @Published private(set) var isProcessingBulkLifecycleAction = false
    @Published private(set) var tailscaleDNSNames: [String: String] = [:]

    private let store = ProfileStore()
    private let gatewayManager = ExclusiveGatewayManager()
    private let terminalControl = TerminalControlService()
    private var processes: [UUID: Process] = [:]
    private var adoptedListeners: [UUID: ListeningProcess] = [:]
    private var outputPipes: [UUID: [Pipe]] = [:]
    private var userStoppedProfiles: Set<UUID> = []
    private var bulkLifecycleTask: Task<Void, Never>?
    private var stopCompletions: [UUID: [() -> Void]] = [:]
    private var tailscaleDNSRefreshes: Set<String> = []

    var onShowSettings: (() -> Void)?
    var onCheckForUpdates: (() -> String)?
    var onInstallUpdate: (() -> String)?

    var serverProfiles: [ServerProfile] { profiles.filter(\.isServer) }
    var runningCount: Int { serverProfiles.filter { phase(for: $0.id) == .running }.count }
    var activeCount: Int { serverProfiles.filter { phase(for: $0.id).isActive }.count }
    var failedCount: Int { serverProfiles.filter { phase(for: $0.id).isFailed }.count }
    var activeLeaseCount: Int { gatewayLeases.count }

    init() {
        Self.shared = self
        gatewayManager.onStateChange = { [weak self] profileID, active, pending in
            Task { @MainActor in
                if let active { self?.gatewayLeases[profileID] = active }
                else { self?.gatewayLeases.removeValue(forKey: profileID) }
                self?.pendingConnections[profileID] = pending
            }
        }
        gatewayManager.onLog = { [weak self] profileID, message in Task { @MainActor in self?.appendLog(profileID, message) } }
        do {
            profiles = try store.load()
            selectedID = profiles.first?.id
            for cliPath in Set(profiles.map(\.tailscalePath)) { refreshTailscaleDNSName(for: cliPath) }
            Task { @MainActor [weak self] in await self?.bootstrapRuntime() }
        } catch { presentedError = "Could not load server profiles: \(error.localizedDescription)" }
        terminalControl.start { [weak self] request in
            await MainActor.run { self?.handleTerminalCommand(request) ?? .error("MCP Controller is unavailable.") }
        }
    }

    func phase(for id: UUID) -> RuntimePhase { phases[id] ?? .stopped }
    func lease(for id: UUID) -> GatewayLeaseSnapshot? { gatewayLeases[id] }
    func waiting(for id: UUID) -> [GatewayPendingSnapshot] { pendingConnections[id] ?? [] }
    func approve(profileID: UUID, clientID: String) { gatewayManager.approve(profileID: profileID, clientID: clientID) }
    func deny(profileID: UUID, clientID: String) { gatewayManager.deny(profileID: profileID, clientID: clientID) }
    func releaseLease(profileID: UUID) { gatewayManager.release(profileID: profileID) }
    func releaseAllLeases() {
        for profile in profiles where lease(for: profile.id) != nil {
            releaseLease(profileID: profile.id)
        }
    }

    func acknowledgeFailureAndReturnLogs(for id: UUID) -> String {
        let text = logs[id] ?? ""
        if phase(for: id).isFailed { phases[id] = .stopped }
        return text
    }

    func add(_ profile: ServerProfile) {
        let insertionIndex = max(0, min(profiles.count, profiles.count))
        profiles.insert(profile, at: insertionIndex)
        selectedID = profile.id
        persist()
    }
    func update(_ profile: ServerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile; persist()
    }

    func duplicate(_ profile: ServerProfile) {
        guard profile.isServer else { return }
        var copy = profile
        copy.id = UUID(); copy.name += " Copy"; copy.autoStart = false; copy.tailscaleRouteEnabled = false
        copy.localPort = nextAvailableLocalPort(startingAt: min(profile.localPort + 1, 65535))
        copy.gatewayPort = nextAvailableGatewayPort(); copy.mountPath = uniqueMountPath(for: copy.name)
        copy.clientCredentials = copy.clientCredentials.map { GatewayClientCredential.generate(name: $0.name) }
        add(copy)
    }

    func defaultProfileTemplate() -> ServerProfile {
        var profile = ServerProfile()
        profile.localPort = nextAvailableLocalPort()
        profile.gatewayPort = nextAvailableGatewayPort()
        profile.mountPath = uniqueMountPath(for: profile.name)
        profile.tailscalePath = TailscaleRouteService.defaultCLIPath
        if UserDefaults.standard.bool(forKey: "settings.oneAIOnly") {
            profile.exclusiveGatewayEnabled = true
            profile.clientCredentials = [.generate(name: "Primary AI")]
        }
        return profile
    }

    @discardableResult
    func saveProfile(_ profile: ServerProfile) -> ServerProfile {
        if profiles.contains(where: { $0.id == profile.id }) { update(profile) }
        else { add(profile) }
        return profile
    }

    @discardableResult
    func createProfile(name: String, description: String, executablePath: String, workingDirectory: String, localPort: Int?) -> ServerProfile {
        var profile = defaultProfileTemplate()
        profile.name = name
        profile.description = description
        profile.executablePath = executablePath
        profile.workingDirectory = workingDirectory
        if let localPort { profile.localPort = localPort }
        if profile.gatewayPort == profile.localPort {
            profile.gatewayPort = nextAvailableGatewayPort(startingAt: min(profile.localPort + 1, 65_535))
        }
        profile.mountPath = uniqueMountPath(for: profile.name)
        add(profile)
        return profile
    }

    @discardableResult
    func createHeading(title: String, index: Int? = nil) -> ServerProfile {
        var profile = ServerProfile()
        profile.kind = .heading
        profile.name = title
        let insertion = max(0, min(index ?? profiles.count, profiles.count))
        profiles.insert(profile, at: insertion)
        selectedID = profile.id
        persist()
        return profile
    }

    @discardableResult
    func createSpacer(index: Int? = nil) -> ServerProfile {
        var profile = ServerProfile()
        profile.kind = .spacer
        profile.name = ""
        let insertion = max(0, min(index ?? profiles.count, profiles.count))
        profiles.insert(profile, at: insertion)
        selectedID = profile.id
        persist()
        return profile
    }

    func moveItem(withID id: UUID, toIndex index: Int) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        moveProfiles(withIDs: [id], toFilteredIndex: index, filteredIDs: profiles.map(\.id))
        return true
    }

    func remoteURL(for profile: ServerProfile) -> String? {
        guard profile.isServer, profile.tailscaleRouteEnabled, profile.exposureMode != .disabled else { return nil }
        if let dnsName = tailscaleDNSNames[profile.tailscalePath], !dnsName.isEmpty {
            return TailscaleRouteService.address(for: profile, dnsName: dnsName)
        }
        refreshTailscaleDNSName(for: profile.tailscalePath)
        return nil
    }

    private func refreshTailscaleDNSName(for cliPath: String) {
        guard !tailscaleDNSRefreshes.contains(cliPath) else { return }
        tailscaleDNSRefreshes.insert(cliPath)
        Task { @MainActor [weak self] in
            let dnsName = await TailscaleRouteService.dnsNameAsync(cliPath: cliPath)
            guard let self else { return }
            self.tailscaleDNSRefreshes.remove(cliPath)
            if let dnsName, !dnsName.isEmpty { self.tailscaleDNSNames[cliPath] = dnsName }
        }
    }

    func applyDefaultTailscaleCLIToAllProfiles() {
        for original in serverProfiles {
            var profile = original
            profile.tailscalePath = TailscaleRouteService.defaultCLIPath
            if profile != original { update(profile) }
        }
    }

    func moveProfiles(withIDs movedIDs: [UUID], toFilteredIndex destination: Int, filteredIDs: [UUID]) {
        guard !movedIDs.isEmpty else { return }

        let movingIDSet = Set(movedIDs)
        let movingProfiles = profiles.filter { movingIDSet.contains($0.id) }
        guard !movingProfiles.isEmpty else { return }

        let remainingProfiles = profiles.filter { !movingIDSet.contains($0.id) }
        let remainingFilteredIDs = filteredIDs.filter { !movingIDSet.contains($0) }
        let clampedDestination = max(0, min(destination, remainingFilteredIDs.count))

        let insertionIndex: Int
        if clampedDestination >= remainingFilteredIDs.count {
            insertionIndex = remainingProfiles.count
        } else if let anchorID = remainingFilteredIDs[safe: clampedDestination],
                  let anchorIndex = remainingProfiles.firstIndex(where: { $0.id == anchorID }) {
            insertionIndex = anchorIndex
        } else {
            insertionIndex = remainingProfiles.count
        }

        profiles = remainingProfiles
        profiles.insert(contentsOf: movingProfiles, at: insertionIndex)
        persist()
    }

    func remove(_ profile: ServerProfile) {
        guard profile.isServer else {
            profiles.removeAll { $0.id == profile.id }
            selectedID = profiles.first?.id
            persist()
            return
        }
        if profile.tailscaleRouteEnabled { _ = stopTailscaleRoute(profile) }
        stop(profile) { [weak self] in
            guard let self else { return }
            self.profiles.removeAll { $0.id == profile.id }
            self.phases.removeValue(forKey: profile.id); self.logs.removeValue(forKey: profile.id)
            self.gatewayLeases.removeValue(forKey: profile.id); self.pendingConnections.removeValue(forKey: profile.id)
            self.selectedID = self.profiles.first?.id; self.persist()
        }
    }

    func start(_ profile: ServerProfile) {
        guard profile.isServer, !phase(for: profile.id).isActive else { return }
        let errors = profile.validationErrors()
        guard errors.isEmpty else { fail(profile, errors.joined(separator: " ")); return }
        if let conflict = serverProfiles.first(where: { $0.id != profile.id && phase(for: $0.id).isActive && $0.localPort == profile.localPort }) {
            fail(profile, "\(conflict.name) is already using MCP port \(profile.localPort)."); return
        }
        if profile.exclusiveGatewayEnabled,
           let conflict = serverProfiles.first(where: {
               $0.id != profile.id && phase(for: $0.id).isActive && (
                   $0.localPort == profile.gatewayPort ||
                   ($0.exclusiveGatewayEnabled && $0.gatewayPort == profile.gatewayPort)
               )
           }) {
            fail(profile, "\(conflict.name) is already using gateway port \(profile.gatewayPort)."); return
        }
        guard FileManager.default.isExecutableFile(atPath: profile.executablePath) else {
            fail(profile, "The executable does not exist or is not executable: \(profile.executablePath)"); return
        }

        userStoppedProfiles.remove(profile.id)
        phases[profile.id] = .starting
        appendLog(profile.id, "Starting \(profile.name)…\n")
        appendLog(profile.id, profile.startupDiagnosticSummary)
        Task { @MainActor [weak self] in await self?.prepareAndLaunch(profile) }
    }

    private func prepareAndLaunch(_ profile: ServerProfile) async {
        if let listener = await PortInspector.listenerAsync(on: profile.localPort) {
            guard phase(for: profile.id) == .starting else { return }
            if PortInspector.belongsToProfile(listener, profile: profile) { await adopt(listener, for: profile) }
            else { fail(profile, "Port \(profile.localPort) is already used by PID \(listener.pid): \(listener.command)") }
            return
        }
        guard phase(for: profile.id) == .starting else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: profile.executablePath)
        process.arguments = profile.arguments.map { $0.replacingOccurrences(of: "{port}", with: String(profile.localPort)) }
        if !profile.workingDirectory.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: profile.workingDirectory, isDirectory: true) }
        process.environment = launchEnvironment(for: profile)
        let output = Pipe(); let error = Pipe()
        process.standardOutput = output; process.standardError = error
        output.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        error.fileHandleForReading.readabilityHandler = logHandler(for: profile.id)
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.gatewayManager.stop(profileID: profile.id)
                self.processes.removeValue(forKey: profile.id); self.outputPipes.removeValue(forKey: profile.id)
                let wasUserStop = self.userStoppedProfiles.remove(profile.id) != nil
                if wasUserStop || self.phase(for: profile.id) == .stopping || self.phase(for: profile.id) == .stopped {
                    self.phases[profile.id] = .stopped; self.appendLog(profile.id, "Process stopped.\n")
                } else if case .failed = self.phase(for: profile.id) {
                    self.appendLog(profile.id, "Process exited with code \(process.terminationStatus).\n")
                } else {
                    self.phases[profile.id] = process.terminationStatus == 0 ? .stopped : .failed("Exited with code \(process.terminationStatus)")
                    self.appendLog(profile.id, "Process exited with code \(process.terminationStatus).\n")
                }
                self.completeStops(for: profile.id)
            }
        }
        do {
            try process.run(); processes[profile.id] = process; outputPipes[profile.id] = [output, error]
            await waitForListener(profile)
        } catch { fail(profile, "Could not start \(profile.name): \(error.localizedDescription)") }
    }

    private func waitForListener(_ profile: ServerProfile) async {
        let timeout = max(15.0, profile.startupDelaySeconds); let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard phase(for: profile.id) == .starting, processes[profile.id]?.isRunning == true else { return }
            if let listener = await PortInspector.listenerAsync(on: profile.localPort), PortInspector.belongsToProfile(listener, profile: profile) {
                await finishStart(profile); return
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard phase(for: profile.id) == .starting, processes[profile.id]?.isRunning == true else { return }
        fail(profile, "\(profile.name) did not open port \(profile.localPort) within \(Int(timeout)) seconds.")
        processes[profile.id]?.terminate()
    }

    private func bootstrapRuntime() async {
        for profile in serverProfiles {
            guard phase(for: profile.id) == .stopped else { continue }
            if let listener = await PortInspector.listenerAsync(on: profile.localPort), PortInspector.belongsToProfile(listener, profile: profile) {
                await adopt(listener, for: profile)
            } else if profile.autoStart {
                start(profile)
                while phase(for: profile.id) == .starting {
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            await Task.yield()
        }
    }

    private func adopt(_ listener: ListeningProcess, for profile: ServerProfile) async {
        do {
            try await Task.detached(priority: .utility) { [gatewayManager] in try gatewayManager.start(profile: profile) }.value
            try await enableExposure(profile)
            guard phase(for: profile.id) != .stopping else { return }
            adoptedListeners[profile.id] = listener; phases[profile.id] = .running
            appendLog(profile.id, "Adopted existing \(profile.name) listener (PID \(listener.pid)) on port \(profile.localPort).\n")
        } catch { fail(profile, "Found \(profile.name), but could not adopt its gateway or exposure: \(error.localizedDescription)") }
    }

    private func finishStart(_ profile: ServerProfile) async {
        guard processes[profile.id]?.isRunning == true, phase(for: profile.id) == .starting else { return }
        do {
            try await Task.detached(priority: .utility) { [gatewayManager] in try gatewayManager.start(profile: profile) }.value
            try await enableExposure(profile)
            guard processes[profile.id]?.isRunning == true, phase(for: profile.id) == .starting else { return }
            phases[profile.id] = .running; appendLog(profile.id, exposureMessage(for: profile))
        } catch {
            gatewayManager.stop(profileID: profile.id)
            fail(profile, "\(profile.name) started, but its gateway or exposure failed: \(error.localizedDescription)")
            processes[profile.id]?.terminate()
        }
    }

    func stop(_ profile: ServerProfile, completion: (() -> Void)? = nil) {
        if let completion { stopCompletions[profile.id, default: []].append(completion) }
        guard phase(for: profile.id).isActive || adoptedListeners[profile.id] != nil else {
            phases[profile.id] = .stopped; completeStops(for: profile.id); return
        }
        phases[profile.id] = .stopping
        userStoppedProfiles.insert(profile.id)
        gatewayManager.stop(profileID: profile.id)

        if let listener = adoptedListeners.removeValue(forKey: profile.id) {
            Task { @MainActor [weak self] in await self?.stopAdopted(listener, profile: profile) }
        } else if let process = processes[profile.id], process.isRunning {
            process.terminate()
            Task { @MainActor [weak self, weak process] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, let process, process.isRunning, self.phase(for: profile.id) == .stopping else { return }
                _ = try? await CommandRunner.runAsync(executable: "/bin/kill", arguments: ["-KILL", String(process.processIdentifier)])
            }
        } else {
            phases[profile.id] = .stopped
            appendLog(profile.id, "Stopped server and released the AI lease. Tailscale Funnel is managed separately.\n")
            completeStops(for: profile.id)
        }
    }

    private func stopAdopted(_ listener: ListeningProcess, profile: ServerProfile) async {
        do {
            try await PortInspector.terminateAsync(listener)
            for _ in 0..<20 {
                guard let current = await PortInspector.listenerAsync(on: profile.localPort), current.pid == listener.pid else { break }
                try? await Task.sleep(for: .milliseconds(150))
            }
            if let current = await PortInspector.listenerAsync(on: profile.localPort), current.pid == listener.pid {
                _ = try? await CommandRunner.runAsync(executable: "/bin/kill", arguments: ["-KILL", String(listener.pid)])
            }
            phases[profile.id] = .stopped
            appendLog(profile.id, "Stopped server and released the AI lease. Tailscale Funnel is managed separately.\n")
            completeStops(for: profile.id)
        } catch {
            if let current = await PortInspector.listenerAsync(on: profile.localPort), current.pid == listener.pid {
                fail(profile, "Could not stop adopted PID \(listener.pid): \(error.localizedDescription)")
                completeStops(for: profile.id)
                return
            }
            phases[profile.id] = .stopped
            appendLog(profile.id, "Adopted PID \(listener.pid) had already exited; continuing shutdown.\n")
            completeStops(for: profile.id)
        }
    }

    private func completeStops(for id: UUID) {
        let completions = stopCompletions.removeValue(forKey: id) ?? []
        completions.forEach { $0() }
    }

    func startAll() {
        let queue = serverProfiles.map(\.id).filter { !phase(for: $0).isActive }
        guard !queue.isEmpty else { return }
        bulkLifecycleTask?.cancel()
        isProcessingBulkLifecycleAction = true
        bulkLifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.bulkLifecycleTask = nil; self.isProcessingBulkLifecycleAction = false }
            for id in queue {
                if Task.isCancelled { return }
                guard let profile = self.profiles.first(where: { $0.id == id }) else { continue }
                self.start(profile)
                while self.phase(for: id) == .starting {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                await Task.yield()
            }
        }
    }

    func stopAll() {
        let queue = serverProfiles.map(\.id).filter { phase(for: $0).isActive }
        guard !queue.isEmpty else { return }
        bulkLifecycleTask?.cancel()
        isProcessingBulkLifecycleAction = true
        bulkLifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.bulkLifecycleTask = nil; self.isProcessingBulkLifecycleAction = false }
            for id in queue {
                if Task.isCancelled { return }
                guard let profile = self.profiles.first(where: { $0.id == id }) else { continue }
                self.stop(profile)
                while self.phase(for: id).isActive {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                await Task.yield()
            }
        }
    }


    func stopImmediatelyForApplicationQuit() {
        bulkLifecycleTask?.cancel()
        flushPersistNow()
        for profile in serverProfiles {
            gatewayManager.stop(profileID: profile.id)
            if let listener = adoptedListeners.removeValue(forKey: profile.id) {
                _ = Darwin.kill(listener.pid, SIGTERM)
            }
            if let process = processes[profile.id], process.isRunning {
                process.terminate()
            }
            phases[profile.id] = .stopped
        }
        processes.removeAll()
        outputPipes.removeAll()
        stopCompletions.removeAll()
    }

    func clearLog(for id: UUID) { logs[id] = "" }
    private func fail(_ profile: ServerProfile, _ message: String) { phases[profile.id] = .failed(message); presentedError = message; appendLog(profile.id, message + "\n") }

    private func launchEnvironment(for profile: ServerProfile) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging(profile.environment) { _, configured in configured }
        let standardPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init); var seen = Set<String>()
        environment["PATH"] = (standardPaths + existing).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    private func enableExposure(_ profile: ServerProfile) async throws {
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: profile) else { return }
        let result = try await CommandRunner.runAsync(executable: profile.tailscalePath, arguments: arguments)
        guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
        tailscaleFunnelRunning = true; UserDefaults.standard.set(true, forKey: "tailscale.funnelRunning")
    }

    private func exposureMessage(for profile: ServerProfile) -> String {
        let gate = profile.exclusiveGatewayEnabled ? " through its exclusive AI gateway" : ""
        guard profile.tailscaleRouteEnabled else { return "Running locally\(gate) on port \(profile.exposedLocalPort).\n" }
        return switch profile.exposureMode {
        case .disabled: "Running locally\(gate) on port \(profile.exposedLocalPort).\n"
        case .tailnet: "Running\(gate); its independent Tailnet route remains available at \(profile.normalizedMountPath).\n"
        case .funnel: "Running\(gate); its independent Funnel route is available at \(profile.normalizedMountPath).\n"
        }
    }

    private func logHandler(for id: UUID) -> @Sendable (FileHandle) -> Void {
        { [weak self] handle in
            let data = handle.availableData; guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.appendLog(id, text) }
        }
    }
    private func appendLog(_ id: UUID, _ text: String) { logs[id] = String(((logs[id] ?? "") + text).suffix(100_000)) }
    private func persist(immediate: Bool = false) {
        do { try store.save(profiles) } catch { presentedError = "Could not save server profiles: \(error.localizedDescription)" }
    }

    func flushPersistNow() {
        persist(immediate: true)
    }
}

enum ControllerError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? { switch self { case .commandFailed(let message): message.trimmingCharacters(in: .whitespacesAndNewlines) } }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
