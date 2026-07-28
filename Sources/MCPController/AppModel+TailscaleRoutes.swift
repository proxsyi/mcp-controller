import Foundation

extension AppModel {
    func nextAvailableLocalPort(startingAt start: Int = 4100) -> Int {
        let used = Set(profiles.map(\.localPort))
        return (max(1024, start)...65535).first(where: { !used.contains($0) }) ?? max(4100, start)
    }

    func nextAvailableGatewayPort(startingAt start: Int = 39000) -> Int {
        let used = Set(profiles.map(\.gatewayPort) + profiles.map(\.localPort))
        return (max(1024, start)...65535).first(where: { !used.contains($0) }) ?? max(39000, start)
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

    func startTailscaleFunnel() {
        let routes = profiles.filter(\.tailscaleRouteEnabled)
        guard !routes.isEmpty else {
            presentedError = "Configure at least one server in Settings → Tailscale before starting Funnel."
            tailscaleFunnelRunning = false
            UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
            return
        }

        var failures: [String] = []
        var started = 0
        for profile in routes {
            guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath),
                  let arguments = TailscaleCommandBuilder.enableArguments(for: profile) else {
                failures.append("\(profile.name): Tailscale CLI or route configuration is invalid")
                continue
            }
            do {
                let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
                if result.exitCode == 0 { started += 1 }
                else { failures.append("\(profile.name): \(result.error.isEmpty ? result.output : result.error)") }
            } catch { failures.append("\(profile.name): \(error.localizedDescription)") }
        }

        tailscaleFunnelRunning = started > 0
        UserDefaults.standard.set(tailscaleFunnelRunning, forKey: "tailscale.funnelRunning")
        if !failures.isEmpty { presentedError = "Some Tailscale routes could not start:\n" + failures.joined(separator: "\n") }
    }

    func stopTailscaleFunnel() {
        var failures: [String] = []
        for profile in profiles where profile.tailscaleRouteEnabled {
            guard let arguments = TailscaleCommandBuilder.removeArguments(for: profile) else { continue }
            do {
                let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
                let message = (result.error + result.output).lowercased()
                if result.exitCode != 0 && !message.contains("handler does not exist") && !message.contains("failed to remove web serve") {
                    failures.append("\(profile.name): \(result.error.isEmpty ? result.output : result.error)")
                }
            } catch { failures.append("\(profile.name): \(error.localizedDescription)") }
        }
        tailscaleFunnelRunning = false
        UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
        if !failures.isEmpty { presentedError = "Some Tailscale routes could not be removed:\n" + failures.joined(separator: "\n") }
    }

    @discardableResult
    func startTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath) else { presentedError = "Tailscale CLI was not found at \(profile.tailscalePath)."; return false }
        if let conflict = profiles.first(where: { $0.id != profile.id && $0.tailscaleRouteEnabled && $0.publicPort == profile.publicPort && $0.normalizedMountPath == profile.normalizedMountPath }) {
            presentedError = "\(conflict.name) already uses HTTPS port \(profile.publicPort) at \(profile.normalizedMountPath)."; return false
        }
        var configured = profile; configured.tailscaleRouteEnabled = true
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: configured) else { presentedError = "Choose Tailnet or Public Funnel before starting the route."; return false }
        do {
            let result = try CommandRunner.run(executable: configured.tailscalePath, arguments: arguments)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            update(configured); tailscaleFunnelRunning = true
            UserDefaults.standard.set(true, forKey: "tailscale.funnelRunning")
            return true
        } catch { presentedError = "Could not start the Tailscale route for \(profile.name): \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func stopTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard let arguments = TailscaleCommandBuilder.removeArguments(for: profile) else { return true }
        do {
            let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
            let message = (result.error + result.output).lowercased()
            guard result.exitCode == 0 || message.contains("handler does not exist") || message.contains("failed to remove web serve") else {
                throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error)
            }
            var configured = profile; configured.tailscaleRouteEnabled = false; update(configured)
            return true
        } catch { presentedError = "Could not remove the Tailscale route for \(profile.name): \(error.localizedDescription)"; return false }
    }
}
