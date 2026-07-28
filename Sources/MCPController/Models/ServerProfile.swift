import Foundation

enum ExposureMode: String, Codable, CaseIterable, Identifiable {
    case disabled, tailnet, funnel
    var id: String { rawValue }
    var title: String { switch self { case .disabled: "Local only"; case .tailnet: "Tailnet"; case .funnel: "Public Funnel" } }
}

struct GatewayClientCredential: Identifiable, Codable, Hashable, Sendable {
    var id = UUID(); var name: String; var token: String
    static func generate(name: String) -> GatewayClientCredential {
        GatewayClientCredential(name: name, token: [UUID(), UUID()].map { $0.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined())
    }
}

struct ServerProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "New MCP Server"
    var description = ""
    var executablePath = ""
    var arguments: [String] = []
    var workingDirectory = ""
    var environment: [String: String] = [:]
    var localPort = 3000
    var exposureMode: ExposureMode = .disabled
    var tailscaleRouteEnabled = false
    var publicPort = 443
    var mountPath = "/"
    var tailscalePath = TailscaleRouteService.defaultCLIPath
    var startupDelaySeconds = 1.0
    var autoStart = false
    var exclusiveGatewayEnabled = false
    var gatewayPort = 39000
    var leaseTimeoutSeconds = 900
    var allowedOrigins: [String] = []
    var clientCredentials: [GatewayClientCredential] = []

    var normalizedMountPath: String {
        let trimmed = mountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "/" }
        let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
    }
    var exposedLocalPort: Int { exclusiveGatewayEnabled ? gatewayPort : localPort }

    func validationErrors() -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Name is required.") }
        if executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Executable path is required.") }
        if !(1...65535).contains(localPort) { errors.append("Local port must be between 1 and 65535.") }
        if exposureMode == .funnel && ![443, 8443, 10000].contains(publicPort) { errors.append("Funnel supports public ports 443, 8443, and 10000.") }
        if tailscaleRouteEnabled && exposureMode == .disabled { errors.append("Choose Tailnet or Public Funnel before enabling a Tailscale route.") }
        if exposureMode != .disabled && !TailscaleRouteService.isCLIAvailable(at: tailscalePath) { errors.append("The Tailscale CLI could not be found at \(tailscalePath).") }
        if exclusiveGatewayEnabled {
            if !(1...65535).contains(gatewayPort) { errors.append("Gateway port must be between 1 and 65535.") }
            if gatewayPort == localPort { errors.append("Gateway and upstream MCP ports must be different.") }
            if !(30...86_400).contains(leaseTimeoutSeconds) { errors.append("Exclusive lease timeout must be between 30 seconds and 24 hours.") }
            if clientCredentials.isEmpty { errors.append("Add at least one AI access key before enabling exclusive access.") }
        }
        return errors
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, executablePath, arguments, workingDirectory, environment
        case localPort, exposureMode, tailscaleRouteEnabled, publicPort, mountPath, tailscalePath
        case startupDelaySeconds, autoStart, exclusiveGatewayEnabled, gatewayPort, leaseTimeoutSeconds, allowedOrigins, clientCredentials
    }

    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try v.decodeIfPresent(String.self, forKey: .name) ?? "New MCP Server"
        description = try v.decodeIfPresent(String.self, forKey: .description) ?? ""
        executablePath = try v.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        arguments = try v.decodeIfPresent([String].self, forKey: .arguments) ?? []
        workingDirectory = try v.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        environment = try v.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        localPort = try v.decodeIfPresent(Int.self, forKey: .localPort) ?? 3000
        exposureMode = try v.decodeIfPresent(ExposureMode.self, forKey: .exposureMode) ?? .disabled
        tailscaleRouteEnabled = try v.decodeIfPresent(Bool.self, forKey: .tailscaleRouteEnabled) ?? false
        publicPort = try v.decodeIfPresent(Int.self, forKey: .publicPort) ?? 443
        mountPath = try v.decodeIfPresent(String.self, forKey: .mountPath) ?? "/"
        let storedPath = try v.decodeIfPresent(String.self, forKey: .tailscalePath) ?? ""
        tailscalePath = storedPath.isEmpty || !TailscaleRouteService.isCLIAvailable(at: storedPath) ? TailscaleRouteService.defaultCLIPath : storedPath
        startupDelaySeconds = try v.decodeIfPresent(Double.self, forKey: .startupDelaySeconds) ?? 1
        autoStart = try v.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        exclusiveGatewayEnabled = try v.decodeIfPresent(Bool.self, forKey: .exclusiveGatewayEnabled) ?? false
        gatewayPort = try v.decodeIfPresent(Int.self, forKey: .gatewayPort) ?? 39000
        leaseTimeoutSeconds = try v.decodeIfPresent(Int.self, forKey: .leaseTimeoutSeconds) ?? 900
        allowedOrigins = try v.decodeIfPresent([String].self, forKey: .allowedOrigins) ?? []
        clientCredentials = try v.decodeIfPresent([GatewayClientCredential].self, forKey: .clientCredentials) ?? []
    }
}

enum RuntimePhase: Equatable {
    case stopped, starting, running, stopping, failed(String)
    var title: String { switch self { case .stopped: "Stopped"; case .starting: "Starting"; case .running: "Running"; case .stopping: "Stopping"; case .failed: "Failed" } }
    var isActive: Bool { switch self { case .starting, .running, .stopping: true; case .stopped, .failed: false } }
    var isFailed: Bool { if case .failed = self { return true }; return false }
}
