import AppKit
import Foundation

extension AppModel {
    func handleTerminalCommand(_ request: TerminalControlRequest) -> TerminalControlResponse {
        let action = request.action.lowercased()
        switch action {
        case "list", "status":
            let rows = profiles.map { profile in
                ["id": profile.id.uuidString, "name": profile.name, "state": phase(for: profile.id).title,
                 "localPort": String(profile.localPort), "gatewayPort": String(profile.gatewayPort),
                 "remotePath": profile.normalizedMountPath, "compatibility": String(profile.remoteClientCompatibilityEnabled)]
            }
            return .ok("\(rows.count) server(s)", payload: jsonString(rows))
        case "show", "export":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            var visible = profile
            if request.arguments["secrets"] != "true" {
                visible.environment = visible.environment.mapValues { _ in "<redacted>" }
                visible.clientCredentials = visible.clientCredentials.map { .init(id: $0.id, name: $0.name, token: "<redacted>") }
            }
            guard let data = try? JSONEncoder.pretty.encode(visible) else { return .error("Could not encode the server profile.") }
            return .ok(profile.name, payload: String(decoding: data, as: UTF8.self))
        case "import":
            guard let json = request.arguments["json"], let data = json.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(ServerProfile.self, from: data) else { return .error("Pass a complete ServerProfile JSON document.") }
            if profiles.contains(where: { $0.id == profile.id }) { update(profile) } else { add(profile) }
            return .ok("Saved \(profile.name).")
        case "start", "stop", "restart", "duplicate", "remove", "route-start", "route-stop", "lease-release":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            switch action {
            case "start": start(profile)
            case "stop": stop(profile)
            case "restart": stop(profile) { [weak self] in self?.start(profile) }
            case "duplicate": duplicate(profile)
            case "remove": remove(profile)
            case "route-start": if !startTailscaleRoute(profile) { return .error(presentedError ?? "Route could not start.") }
            case "route-stop": if !stopTailscaleRoute(profile) { return .error(presentedError ?? "Route could not stop.") }
            default: releaseLease(profileID: profile.id)
            }
            return .ok("\(action) accepted for \(profile.name).")
        case "start-all": startAll(); return .ok("Started all configured servers.")
        case "stop-all": stopAll(); return .ok("Stopped all managed servers.")
        case "logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            return .ok(profile.name, payload: logs[profile.id] ?? "")
        case "clear-logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            clearLog(for: profile.id); return .ok("Cleared logs for \(profile.name).")
        case "funnel-start": startTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes started.") : .error(presentedError!)
        case "funnel-stop": stopTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes stopped.") : .error(presentedError!)
        case "funnel-status": return .ok(tailscaleFunnelRunning ? "running" : "stopped")
        case "one-ai":
            let enabled = request.arguments["enabled"] == "true"
            applyGlobalOneAIPolicy(enabled); UserDefaults.standard.set(enabled, forKey: "settings.oneAIOnly")
            return .ok("One-AI policy \(enabled ? "enabled" : "disabled").")
        case "open": NSApplication.shared.activate(ignoringOtherApps: true); return .ok("Opened MCP Controller.")
        case "quit": shutdownForApplicationQuit(); NSApplication.shared.terminate(nil); return .ok("Quitting MCP Controller.")
        default: return .error("Unknown action: \(request.action)")
        }
    }

    private func terminalProfile(_ target: String?) -> ServerProfile? {
        guard let target else { return nil }
        if let id = UUID(uuidString: target), let profile = profiles.first(where: { $0.id == id }) { return profile }
        return profiles.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    private func jsonString(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
