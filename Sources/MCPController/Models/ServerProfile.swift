import Foundation

enum ExposureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case disabled, tailnet, funnel
    var id: String { rawValue }
    var title: String { switch self { case .disabled: "Local only"; case .tailnet: "Tailnet"; case .funnel: "Public Funnel" } }
}

enum ProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case server, heading, spacer
    var id: String { rawValue }
}

struct GatewayClientCredential: Identifiable, Codable, Hashable, Sendable {
    var id = UUID(); var name: String; var token: String
    static func generate(name: String) -> GatewayClientCredential {
        GatewayClientCredential(name: name, token: [UUID(), UUID()].map { $0.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined())
    }
}

struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID(); var kind: ProfileKind = .server; var name = "New MCP Server"; var description = ""; var executablePath = ""
    var arguments: [String] = []; var workingDirectory = ""; var environment: [String: String] = [:]
    var localPort = 3000; var exposureMode: ExposureMode = .disabled; var tailscaleRouteEnabled = false
    var publicPort = 443; var mountPath = "/"; var tailscalePath = TailscaleRouteService.defaultCLIPath
    var startupDelaySeconds = 15.0; var autoStart = false; var exclusiveGatewayEnabled = false
    var remoteClientCompatibilityEnabled = false
    var gatewayPort = 39000; var leaseTimeoutSeconds = 900; var publicRequestTimeoutSeconds = 300; var allowedOrigins: [String] = []
    var clientCredentials: [GatewayClientCredential] = []

    var isServer: Bool { kind == .server }
    var isHeading: Bool { kind == .heading }
    var isSpacer: Bool { kind == .spacer }

    var normalizedMountPath: String {
        guard isServer else { return "/" }
        let trimmed = mountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "/" }
        let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
    }
    var exposedLocalPort: Int { exclusiveGatewayEnabled ? gatewayPort : localPort }

    var streamableHTTPPath: String? {
        guard isServer else { return nil }
        if let index = arguments.firstIndex(of: "--streamableHttpPath"), arguments.indices.contains(index + 1) {
            return Self.normalizedEndpointPath(arguments[index + 1])
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--streamableHttpPath=") }) {
            return Self.normalizedEndpointPath(String(argument.dropFirst("--streamableHttpPath=".count)))
        }
        if let index = arguments.firstIndex(of: "--transport"), arguments.indices.contains(index + 1) {
            let transport = arguments[index + 1].lowercased()
            if transport == "streamable-http" || transport == "streamablehttp" {
                return "/mcp"
            }
        }
        if arguments.contains(where: {
            let value = $0.lowercased()
            return value == "--transport=streamable-http" || value == "--transport=streamablehttp"
        }) {
            return "/mcp"
        }
        return nil
    }

    private static func normalizedEndpointPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    func validationErrors() -> [String] {
        if isSpacer { return [] }
        if isHeading {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ["Heading title is required."] : []
        }
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Name is required.") }
        if executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Executable path is required.") }
        if !(1024...65535).contains(localPort) { errors.append("MCP server port must be 1024 or higher. Public HTTPS port 443 is configured separately in Settings → Tailscale.") }
        if exposureMode == .funnel && ![443, 8443, 10000].contains(publicPort) { errors.append("Funnel supports public ports 443, 8443, and 10000.") }
        if tailscaleRouteEnabled && exposureMode == .disabled { errors.append("Choose Tailnet or Public Funnel in Settings → Tailscale.") }
        if tailscaleRouteEnabled && !TailscaleRouteService.isCLIAvailable(at: tailscalePath) { errors.append("The Tailscale CLI could not be found at \(tailscalePath).") }
        if exclusiveGatewayEnabled {
            if !(1024...65535).contains(gatewayPort) { errors.append("Gateway port must be between 1024 and 65535.") }
            if gatewayPort == localPort { errors.append("Gateway and upstream MCP ports must be different.") }
            if !(30...86_400).contains(leaseTimeoutSeconds) { errors.append("Exclusive lease timeout must be between 30 seconds and 24 hours.") }
            if !(30...3_600).contains(publicRequestTimeoutSeconds) { errors.append("Public request timeout must be between 30 seconds and 60 minutes.") }
            if clientCredentials.isEmpty { errors.append("Add at least one AI access key before enabling exclusive access.") }
        }
        return errors
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, description, executablePath, arguments, workingDirectory, environment, localPort, exposureMode
        case tailscaleRouteEnabled, publicPort, mountPath, tailscalePath, startupDelaySeconds, autoStart
        case exclusiveGatewayEnabled, remoteClientCompatibilityEnabled, gatewayPort, leaseTimeoutSeconds, publicRequestTimeoutSeconds, allowedOrigins, clientCredentials
    }
    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(); kind = try v.decodeIfPresent(ProfileKind.self, forKey: .kind) ?? .server; name = try v.decodeIfPresent(String.self, forKey: .name) ?? "New MCP Server"
        description = try v.decodeIfPresent(String.self, forKey: .description) ?? ""; executablePath = try v.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        arguments = try v.decodeIfPresent([String].self, forKey: .arguments) ?? []; workingDirectory = try v.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        environment = try v.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]; localPort = try v.decodeIfPresent(Int.self, forKey: .localPort) ?? 3000
        exposureMode = try v.decodeIfPresent(ExposureMode.self, forKey: .exposureMode) ?? .disabled; tailscaleRouteEnabled = try v.decodeIfPresent(Bool.self, forKey: .tailscaleRouteEnabled) ?? false
        publicPort = try v.decodeIfPresent(Int.self, forKey: .publicPort) ?? 443; mountPath = try v.decodeIfPresent(String.self, forKey: .mountPath) ?? "/"
        let storedPath = try v.decodeIfPresent(String.self, forKey: .tailscalePath) ?? ""
        tailscalePath = storedPath.isEmpty || !TailscaleRouteService.isCLIAvailable(at: storedPath) ? TailscaleRouteService.defaultCLIPath : storedPath
        startupDelaySeconds = max(15, try v.decodeIfPresent(Double.self, forKey: .startupDelaySeconds) ?? 15)
        autoStart = try v.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        exclusiveGatewayEnabled = try v.decodeIfPresent(Bool.self, forKey: .exclusiveGatewayEnabled) ?? false
        remoteClientCompatibilityEnabled = try v.decodeIfPresent(Bool.self, forKey: .remoteClientCompatibilityEnabled) ?? false
        gatewayPort = try v.decodeIfPresent(Int.self, forKey: .gatewayPort) ?? 39000
        leaseTimeoutSeconds = try v.decodeIfPresent(Int.self, forKey: .leaseTimeoutSeconds) ?? 900
        publicRequestTimeoutSeconds = try v.decodeIfPresent(Int.self, forKey: .publicRequestTimeoutSeconds) ?? 300
        allowedOrigins = try v.decodeIfPresent([String].self, forKey: .allowedOrigins) ?? []
        clientCredentials = try v.decodeIfPresent([GatewayClientCredential].self, forKey: .clientCredentials) ?? []
    }
}

enum RuntimePhase: Equatable, Sendable {
    case stopped, starting, running, stopping, failed(String)
    var title: String { switch self { case .stopped: "Stopped"; case .starting: "Starting"; case .running: "Running"; case .stopping: "Stopping"; case .failed: "Failed" } }
    var isActive: Bool { switch self { case .starting, .running, .stopping: true; case .stopped, .failed: false } }
    var isFailed: Bool { if case .failed = self { return true }; return false }
}
