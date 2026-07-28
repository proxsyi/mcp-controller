import Foundation

extension AppModel {
    func nextAvailableLocalPort(startingAt start: Int = 4100) -> Int {
        let used = Set(profiles.map(\.localPort))
        return (start...65535).first(where: { !used.contains($0) }) ?? start
    }

    func nextAvailableGatewayPort(startingAt start: Int = 39000) -> Int {
        let used = Set(profiles.map(\.gatewayPort) + profiles.map(\.localPort))
        return (start...65535).first(where: { !used.contains($0) }) ?? start
    }

    func uniqueMountPath(for name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        let base = "/mcp/\(slug.isEmpty ? "server" : slug)"
        let used = Set(profiles.map(\.normalizedMountPath))
        if !used.contains(base) { return base }
        var suffix = 2
        while used.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }

    @discardableResult
    func startTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard phase(for: profile.id) == .running else { presentedError = "Start \(profile.name) before enabling its Tailscale route."; return false }
        guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath) else { presentedError = "Tailscale CLI was not found at \(profile.tailscalePath)."; return false }
        if let conflict = profiles.first(where: { $0.id != profile.id && $0.tailscaleRouteEnabled && $0.publicPort == profile.publicPort && $0.normalizedMountPath == profile.normalizedMountPath }) {
            presentedError = "\(conflict.name) already uses HTTPS port \(profile.publicPort) at \(profile.normalizedMountPath)."
            return false
        }
        var configured = profile; configured.tailscaleRouteEnabled = true
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: configured) else { presentedError = "Choose Tailnet or Public Funnel before starting the route."; return false }
        do {
            let result = try CommandRunner.run(executable: configured.tailscalePath, arguments: arguments)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            update(configured); return true
        } catch { presentedError = "Could not start the Tailscale route for \(profile.name): \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func stopTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard let arguments = TailscaleCommandBuilder.disableArguments(for: profile) else { return true }
        do {
            let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            var configured = profile; configured.tailscaleRouteEnabled = false; update(configured); return true
        } catch { presentedError = "Could not stop the Tailscale route for \(profile.name): \(error.localizedDescription)"; return false }
    }
}
