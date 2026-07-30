import AppKit
import Foundation

extension AppModel {
    func handleTerminalCommand(_ request: TerminalControlRequest) -> TerminalControlResponse {
        let action = request.action.lowercased()
        switch action {
        case "list", "status":
            if let profile = terminalProfile(request.target) {
                return .ok(profile.name, payload: jsonString([terminalSummary(for: profile)]))
            }
            return .ok("\(profiles.count) server(s)", payload: jsonString(profiles.map(terminalSummary)))
        case "show", "export":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            var visible = profile
            if request.arguments["secrets"] != "true" {
                visible.environment = visible.environment.mapValues { _ in "<redacted>" }
                visible.clientCredentials = visible.clientCredentials.map { .init(id: $0.id, name: $0.name, token: "<redacted>") }
            }
            guard let data = try? JSONEncoder.pretty.encode(visible) else { return .error("Could not encode the server profile.") }
            return .ok(profile.name, payload: String(decoding: data, as: UTF8.self))
        case "template":
            let profile = defaultProfileTemplate()
            guard let data = try? JSONEncoder.pretty.encode(profile) else { return .error("Could not encode a template profile.") }
            return .ok("Generated a profile template.", payload: String(decoding: data, as: UTF8.self))
        case "new":
            guard let name = request.arguments["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return .error("Pass --name for the new server.")
            }
            guard let executablePath = request.arguments["executablePath"]?.trimmingCharacters(in: .whitespacesAndNewlines), !executablePath.isEmpty else {
                return .error("Pass --executable with the absolute executable path.")
            }
            let created = createProfile(
                name: name,
                description: request.arguments["description"] ?? "",
                executablePath: executablePath,
                workingDirectory: request.arguments["workingDirectory"] ?? "",
                localPort: request.arguments["localPort"].flatMap(Int.init)
            )
            return .ok("Created \(created.name).", payload: jsonString(terminalSummary(for: created)))
        case "save", "import":
            guard let json = request.arguments["json"], let data = json.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(ServerProfile.self, from: data) else { return .error("Pass a complete ServerProfile JSON document.") }
            let saved = saveProfile(profile)
            return .ok("Saved \(saved.name).")
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
        case "start-all": startAll(); return .ok("Queued all configured servers to start.")
        case "stop-all": stopAll(); return .ok("Queued all managed servers to stop.")
        case "lease-release-all": releaseAllLeases(); return .ok("Released every active AI lease.")
        case "logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            return .ok(profile.name, payload: logs[profile.id] ?? "")
        case "clear-logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            clearLog(for: profile.id); return .ok("Cleared logs for \(profile.name).")
        case "funnel-start": startTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes started.") : .error(presentedError!)
        case "funnel-stop": stopTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes stopped.") : .error(presentedError!)
        case "funnel-status": return .ok(tailscaleFunnelRunning ? "running" : "stopped")
        case "use-default-cli": applyDefaultTailscaleCLIToAllProfiles(); return .ok("Updated every profile to use the default Tailscale CLI path.")
        case "one-ai":
            let enabled = request.arguments["enabled"] == "true"
            applyGlobalOneAIPolicy(enabled); UserDefaults.standard.set(enabled, forKey: "settings.oneAIOnly")
            return .ok("One-AI policy \(enabled ? "enabled" : "disabled").")
        case "pending":
            return pendingResponse(for: request.target)
        case "lease":
            return leaseResponse(for: request.target)
        case "approve", "deny":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            guard let clientID = request.arguments["clientID"], !clientID.isEmpty else { return .error("Pass --client-id with the waiting client identifier.") }
            if action == "approve" { approve(profileID: profile.id, clientID: clientID) }
            else { deny(profileID: profile.id, clientID: clientID) }
            return .ok("\(action.capitalized)d \(clientID) for \(profile.name).")
        case "keys":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            let rows = profile.clientCredentials.map { ["id": $0.id.uuidString, "name": $0.name, "tokenSuffix": String($0.token.suffix(6))] }
            return .ok(profile.name, payload: jsonString(rows))
        case "key-add":
            guard var profile = terminalProfile(request.target) else { return .error("Server not found.") }
            let provided = request.arguments["keyName"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let credential = GatewayClientCredential.generate(name: provided.isEmpty ? "AI \(profile.clientCredentials.count + 1)" : provided)
            profile.clientCredentials.append(credential)
            saveProfile(profile)
            return .ok("Added \(credential.name) to \(profile.name).", payload: credential.token)
        case "key-remove":
            guard var profile = terminalProfile(request.target) else { return .error("Server not found.") }
            guard let credential = terminalCredential(request.arguments["key"], in: profile) else { return .error("Access key not found.") }
            profile.clientCredentials.removeAll { $0.id == credential.id }
            saveProfile(profile)
            return .ok("Removed \(credential.name) from \(profile.name).")
        case "key-show":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            guard let credential = terminalCredential(request.arguments["key"], in: profile) else { return .error("Access key not found.") }
            return .ok(credential.name, payload: credential.token)
        case "remote-url":
            if let profile = terminalProfile(request.target) {
                guard let url = remoteURL(for: profile) else { return .error("Remote URL is unavailable until Tailscale is connected and remote access is enabled.") }
                return .ok(profile.name, payload: url)
            }
            let urls = profiles.compactMap { profile -> [String: String]? in
                guard let url = remoteURL(for: profile) else { return nil }
                return ["name": profile.name, "url": url]
            }
            return urls.isEmpty ? .error("No remote URLs are currently available.") : .ok("Remote URLs", payload: jsonString(urls))
        case "check-updates":
            guard let onCheckForUpdates else { return .error("Update checks are unavailable.") }
            return .ok(onCheckForUpdates())
        case "install-update":
            guard let onInstallUpdate else { return .error("Update installs are unavailable.") }
            return .ok(onInstallUpdate())
        case "open": NSApplication.shared.activate(ignoringOtherApps: true); return .ok("Opened MCP Controller.")
        case "settings":
            if NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                return .ok("Opened Settings.")
            }
            onShowSettings?()
            return .ok("Opened Settings.")
        case "quit": shutdownForApplicationQuit(); NSApplication.shared.terminate(nil); return .ok("Quitting MCP Controller.")
        default: return .error("Unknown action: \(request.action)")
        }
    }

    private func terminalProfile(_ target: String?) -> ServerProfile? {
        guard let target else { return nil }
        if let id = UUID(uuidString: target), let profile = profiles.first(where: { $0.id == id }) { return profile }
        return profiles.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    private func terminalCredential(_ target: String?, in profile: ServerProfile) -> GatewayClientCredential? {
        guard let target, !target.isEmpty else { return nil }
        if let id = UUID(uuidString: target), let credential = profile.clientCredentials.first(where: { $0.id == id }) { return credential }
        return profile.clientCredentials.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    private func terminalSummary(for profile: ServerProfile) -> [String: String] {
        [
            "id": profile.id.uuidString,
            "name": profile.name,
            "state": phase(for: profile.id).title,
            "localPort": String(profile.localPort),
            "gatewayPort": String(profile.gatewayPort),
            "remotePath": profile.normalizedMountPath,
            "exposureMode": profile.exposureMode.rawValue,
            "routeEnabled": String(profile.tailscaleRouteEnabled),
            "compatibility": String(profile.remoteClientCompatibilityEnabled),
            "exclusiveGateway": String(profile.exclusiveGatewayEnabled),
            "autoStart": String(profile.autoStart),
            "remoteURL": remoteURL(for: profile) ?? ""
        ]
    }

    private func pendingResponse(for target: String?) -> TerminalControlResponse {
        if let profile = terminalProfile(target) {
            let payload: [String: Any] = [
                "profile": profile.name,
                "lease": terminalLeaseSnapshot(for: profile.id) as Any,
                "pending": waiting(for: profile.id).map(terminalPendingSnapshot)
            ]
            return .ok(profile.name, payload: jsonString(payload))
        }
        let payload = profiles.map { profile in
            [
                "profile": profile.name,
                "lease": terminalLeaseSnapshot(for: profile.id) as Any,
                "pending": waiting(for: profile.id).map(terminalPendingSnapshot)
            ] as [String: Any]
        }
        return .ok("Pending access requests", payload: jsonString(payload))
    }

    private func leaseResponse(for target: String?) -> TerminalControlResponse {
        if let profile = terminalProfile(target) {
            return .ok(profile.name, payload: jsonString(terminalLeaseSnapshot(for: profile.id) ?? [:]))
        }
        let payload = profiles.compactMap { profile -> [String: Any]? in
            guard let lease = terminalLeaseSnapshot(for: profile.id) else { return nil }
            return ["profile": profile.name, "lease": lease]
        }
        return .ok("Active leases", payload: jsonString(payload))
    }

    private func terminalLeaseSnapshot(for profileID: UUID) -> [String: String]? {
        guard let lease = lease(for: profileID) else { return nil }
        return [
            "clientID": lease.clientID,
            "clientName": lease.clientName,
            "acquiredAt": ISO8601DateFormatter().string(from: lease.acquiredAt),
            "lastSeenAt": ISO8601DateFormatter().string(from: lease.lastSeenAt)
        ]
    }

    private func terminalPendingSnapshot(_ pending: GatewayPendingSnapshot) -> [String: String] {
        [
            "clientID": pending.clientID,
            "clientName": pending.clientName,
            "requestedAt": ISO8601DateFormatter().string(from: pending.requestedAt)
        ]
    }

    private func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
