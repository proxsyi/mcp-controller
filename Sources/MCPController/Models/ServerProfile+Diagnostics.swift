import Foundation

extension ServerProfile {
    var startupDiagnosticSummary: String {
        let sensitiveMarkers = ["password", "token", "secret", "api-key", "api_key", "apikey", "authorization", "cookie", "session", "bearer", "private-key", "private_key"]
        var redactNextArgument = false
        let safeArguments = arguments.map { argument -> String in
            if redactNextArgument {
                redactNextArgument = false
                return "<redacted>"
            }

            let lowered = argument.lowercased()
            let optionName: String
            if let equals = lowered.firstIndex(of: "=") {
                optionName = String(lowered[..<equals]).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            } else {
                optionName = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }
            guard sensitiveMarkers.contains(where: { optionName.contains($0) }) else { return argument }

            if let equals = argument.firstIndex(of: "=") {
                return String(argument[...equals]) + "<redacted>"
            }
            if argument.hasPrefix("-") {
                redactNextArgument = true
            }
            return argument
        }
        let args = safeArguments.isEmpty ? "(none)" : safeArguments.joined(separator: " | ")
        let directory = workingDirectory.isEmpty ? "(inherited)" : workingDirectory
        let environmentSummary = environment.keys.sorted().map { key in
            let lowered = key.lowercased()
            let sensitive = sensitiveMarkers.contains { lowered.contains($0.replacingOccurrences(of: "-", with: "_")) || lowered.contains($0) }
            return "  \(key)=\(sensitive ? "<redacted>" : environment[key] ?? "")"
        }.joined(separator: "\n")
        let origins = allowedOrigins.isEmpty ? "(none; browser origins denied)" : allowedOrigins.joined(separator: ", ")
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
