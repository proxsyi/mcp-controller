import Foundation

extension ServerProfile {
    var startupDiagnosticSummary: String {
        let args = arguments.isEmpty ? "(none)" : arguments.joined(separator: " | ")
        let directory = workingDirectory.isEmpty ? "(inherited)" : workingDirectory
        let environmentSummary = environment.keys.sorted().map { key in
            let lowered = key.lowercased()
            let sensitive = ["password", "token", "secret", "api_key", "apikey"].contains { lowered.contains($0) }
            return "  \(key)=\(sensitive ? "<redacted>" : environment[key] ?? "")"
        }.joined(separator: "\n")
        let origins = allowedOrigins.isEmpty ? "(any/unspecified)" : allowedOrigins.joined(separator: ", ")
        let keyNames = clientCredentials.isEmpty ? "(none)" : clientCredentials.map(\.name).joined(separator: ", ")
        return """
        --- Server configuration ---
        Name: \(name)
        ID: \(id.uuidString)
        Description: \(description.isEmpty ? "(none)" : description)
        Executable: \(executablePath)
        Arguments: \(args)
        Working directory: \(directory)
        Environment:\n\(environmentSummary.isEmpty ? "  (none)" : environmentSummary)
        Local endpoint: 127.0.0.1:\(localPort)\(streamableHTTPPath ?? "")
        Readiness timeout: \(max(15, Int(startupDelaySeconds)))s
        Start at launch: \(autoStart)
        Remote mode: \(exposureMode.title)
        Route enabled: \(tailscaleRouteEnabled)
        Remote path: \(normalizedMountPath)
        Public HTTPS port: \(publicPort)
        Tailscale CLI: \(tailscalePath)
        Gateway enabled: \(exclusiveGatewayEnabled)
        Gateway endpoint: 127.0.0.1:\(gatewayPort)
        Lease timeout: \(leaseTimeoutSeconds)s
        Public request timeout: \(publicRequestTimeoutSeconds)s
        Allowed origins: \(origins)
        Access keys: \(keyNames) (tokens redacted)
        Remote client compatibility: \(remoteClientCompatibilityEnabled)
        ----------------------------
        """ + "\n"
    }
}
