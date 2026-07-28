import Foundation

enum ExposureMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case tailnet
    case funnel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "Local only"
        case .tailnet: "Tailnet"
        case .funnel: "Public Funnel"
        }
    }
}

struct ServerProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "New MCP Server"
    var executablePath = ""
    var arguments: [String] = []
    var workingDirectory = ""
    var environment: [String: String] = [:]
    var localPort = 3000
    var exposureMode: ExposureMode = .disabled
    var publicPort = 443
    var mountPath = "/"
    var tailscalePath = "/usr/local/bin/tailscale"
    var startupDelaySeconds = 1.0
    var autoStart = false

    var normalizedMountPath: String {
        let trimmed = mountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "/" }
        let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
    }

    func validationErrors() -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name is required.")
        }
        if executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Executable path is required.")
        }
        if !(1...65535).contains(localPort) {
            errors.append("Local port must be between 1 and 65535.")
        }
        if exposureMode == .funnel && ![443, 8443, 10000].contains(publicPort) {
            errors.append("Funnel supports public ports 443, 8443, and 10000.")
        }
        if exposureMode != .disabled && tailscalePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Tailscale CLI path is required when exposure is enabled.")
        }
        return errors
    }
}

enum RuntimePhase: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .failed: "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        case .stopped, .failed: false
        }
    }
}
