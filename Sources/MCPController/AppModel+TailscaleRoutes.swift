import Foundation

extension AppModel {
    func nextAvailableLocalPort(startingAt start: Int = 4100) -> Int {
        let used = Set(serverProfiles.map(\.localPort) + serverProfiles.map(\.gatewayPort))
        return nextAvailablePort(startingAt: start, used: used, defaultStart: 4100)
    }

    func nextAvailableGatewayPort(startingAt start: Int = 39000) -> Int {
        let used = Set(serverProfiles.map(\.gatewayPort) + serverProfiles.map(\.localPort))
        return nextAvailablePort(startingAt: start, used: used, defaultStart: 39000)
    }

    func uniqueMountPath(for name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        let base = "/mcp/\(slug.isEmpty ? "server" : slug)"
        let used = Set(serverProfiles.map(\.normalizedMountPath))
        if !used.contains(base) { return base }
        var suffix = 2
        while used.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }

    func startTailscaleFunnel() async {
        guard TailscaleMutationCoordinator.shared.begin() else {
            presentedError = "Another Tailscale change is already in progress."
            return
        }
        defer { TailscaleMutationCoordinator.shared.end() }
        presentedError = nil
        let routes = serverProfiles.filter { $0.tailscaleRouteEnabled && $0.exposureMode == .funnel }
        guard !routes.isEmpty else {
            presentedError = "Configure at least one Public Funnel server in Settings → Tailscale before starting Funnel."
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
            _ = await removeManagedRoutes(for: profile)
            do {
                let result = try await CommandRunner.runAsync(executable: profile.tailscalePath, arguments: arguments, timeout: 30)
                if result.exitCode == 0 { started += 1 }
                else { failures.append("\(profile.name): \(result.error.isEmpty ? result.output : result.error)") }
            } catch { failures.append("\(profile.name): \(error.localizedDescription)") }
        }

        tailscaleFunnelRunning = started > 0
        UserDefaults.standard.set(tailscaleFunnelRunning, forKey: "tailscale.funnelRunning")
        if !failures.isEmpty { presentedError = "Some Tailscale routes could not start:\n" + failures.joined(separator: "\n") }
    }

    @discardableResult
    func resetManagedTailscaleConnections() async -> Int? {
        guard TailscaleMutationCoordinator.shared.begin() else {
            presentedError = "Another Tailscale change is already in progress."
            return nil
        }
        defer { TailscaleMutationCoordinator.shared.end() }

        presentedError = nil
        let routes = serverProfiles.filter { $0.tailscaleRouteEnabled && $0.exposureMode != .disabled }
        guard !routes.isEmpty else {
            presentedError = "Configure at least one Controller-managed Tailscale route before reconnecting."
            return nil
        }

        // Route recovery is intentionally scoped to paths owned by MCP Controller.
        // Never substitute a global `tailscale funnel reset`, Serve reset, or tailscale down.
        startAll()

        var failures: [String] = []
        var reconnected = 0
        var funnelReconnected = false

        for profile in routes {
            guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath),
                  let arguments = TailscaleCommandBuilder.enableArguments(for: profile) else {
                failures.append("\(profile.name): Tailscale CLI or route configuration is invalid")
                continue
            }

            let removalFailures = await removeManagedRoutes(for: profile)
            if !removalFailures.isEmpty {
                failures.append(contentsOf: removalFailures.map { "\(profile.name): \($0)" })
                continue
            }

            do {
                let result = try await CommandRunner.runAsync(
                    executable: profile.tailscalePath,
                    arguments: arguments,
                    timeout: 30
                )
                if result.exitCode == 0 {
                    reconnected += 1
                    if profile.exposureMode == .funnel { funnelReconnected = true }
                } else {
                    failures.append("\(profile.name): \(result.error.isEmpty ? result.output : result.error)")
                }
            } catch {
                failures.append("\(profile.name): \(error.localizedDescription)")
            }
        }

        tailscaleFunnelRunning = funnelReconnected
        UserDefaults.standard.set(funnelReconnected, forKey: "tailscale.funnelRunning")
        if !failures.isEmpty {
            presentedError = "Some Controller-managed Tailscale routes could not reconnect:\n" + failures.joined(separator: "\n")
        }
        return reconnected
    }

    func stopTailscaleFunnel() async {
        guard TailscaleMutationCoordinator.shared.begin() else {
            presentedError = "Another Tailscale change is already in progress."
            return
        }
        defer { TailscaleMutationCoordinator.shared.end() }
        presentedError = nil
        var failures: [String] = []
        for profile in serverProfiles where profile.tailscaleRouteEnabled && profile.exposureMode == .funnel {
            let errors = await removeManagedRoutes(for: profile)
            failures.append(contentsOf: errors.map { "\(profile.name): \($0)" })
        }
        tailscaleFunnelRunning = false
        UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
        if !failures.isEmpty { presentedError = "Some Tailscale routes could not be removed:\n" + failures.joined(separator: "\n") }
    }

    @discardableResult
    func startTailscaleRoute(_ profile: ServerProfile) async -> Bool {
        guard TailscaleMutationCoordinator.shared.begin() else {
            presentedError = "Another Tailscale change is already in progress."
            return false
        }
        defer { TailscaleMutationCoordinator.shared.end() }
        presentedError = nil
        guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath) else { presentedError = "Tailscale CLI was not found at \(profile.tailscalePath)."; return false }
        if let conflict = serverProfiles.first(where: { $0.id != profile.id && $0.tailscaleRouteEnabled && $0.publicPort == profile.publicPort && $0.normalizedMountPath == profile.normalizedMountPath }) {
            presentedError = "\(conflict.name) already uses HTTPS port \(profile.publicPort) at \(profile.normalizedMountPath)."; return false
        }
        var configured = profile; configured.tailscaleRouteEnabled = true
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: configured) else { presentedError = "Choose Tailnet or Public Funnel before starting the route."; return false }

        let previous = profiles.first(where: { $0.id == configured.id && $0.tailscaleRouteEnabled })
        _ = await removeManagedRoutes(for: configured)
        do {
            let result = try await CommandRunner.runAsync(executable: configured.tailscalePath, arguments: arguments, timeout: 30)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            update(configured)
            if configured.exposureMode == .funnel {
                tailscaleFunnelRunning = true
                UserDefaults.standard.set(true, forKey: "tailscale.funnelRunning")
            }
            return true
        } catch {
            let restored = await restorePreviousRoute(previous)
            let restoreNote = restored ? " The previous route was restored." : ""
            presentedError = "Could not start the Tailscale route for \(profile.name): \(error.localizedDescription)\(restoreNote)"
            return false
        }
    }

    @discardableResult
    func stopTailscaleRoute(_ profile: ServerProfile) async -> Bool {
        guard TailscaleMutationCoordinator.shared.begin() else {
            presentedError = "Another Tailscale change is already in progress."
            return false
        }
        defer { TailscaleMutationCoordinator.shared.end() }
        presentedError = nil
        let errors = await removeManagedRoutes(for: profile)
        guard errors.isEmpty else {
            presentedError = "Could not remove the Tailscale route for \(profile.name): \(errors.joined(separator: "; "))"
            return false
        }
        var configured = profile
        configured.tailscaleRouteEnabled = false
        update(configured)
        if !serverProfiles.contains(where: { $0.id != profile.id && $0.tailscaleRouteEnabled && $0.exposureMode == .funnel }) {
            tailscaleFunnelRunning = false
            UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
        }
        return true
    }

    private func restorePreviousRoute(_ previous: ServerProfile?) async -> Bool {
        guard let previous,
              TailscaleRouteService.isCLIAvailable(at: previous.tailscalePath),
              let restoreArguments = TailscaleCommandBuilder.enableArguments(for: previous) else {
            return false
        }
        do {
            let result = try await CommandRunner.runAsync(executable: previous.tailscalePath, arguments: restoreArguments, timeout: 30)
            guard result.exitCode == 0 else { return false }
            if previous.exposureMode == .funnel {
                tailscaleFunnelRunning = true
                UserDefaults.standard.set(true, forKey: "tailscale.funnelRunning")
            } else if !serverProfiles.contains(where: { $0.id != previous.id && $0.tailscaleRouteEnabled && $0.exposureMode == .funnel }) {
                tailscaleFunnelRunning = false
                UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
            }
            return true
        } catch {
            return false
        }
    }

    private func removeManagedRoutes(for profile: ServerProfile) async -> [String] {
        let paths = managedRoutePaths(for: profile)
        var failures: [String] = []
        for path in paths {
            for arguments in TailscaleCommandBuilder.allRemoveArgumentSets(for: profile, mountPath: path) {
                do {
                    let result = try await CommandRunner.runAsync(executable: profile.tailscalePath, arguments: arguments, timeout: 30)
                    let message = (result.error + result.output).lowercased()
                    if result.exitCode != 0 &&
                        !message.contains("handler does not exist") &&
                        !message.contains("failed to remove web serve") {
                        failures.append(result.error.isEmpty ? result.output : result.error)
                    }
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }
        return failures
    }

    private func managedRoutePaths(for profile: ServerProfile) -> [String] {
        let current = profile.normalizedMountPath
        var paths = [current]
        if !current.hasSuffix("/mcp") { paths.append(current == "/" ? "/mcp" : current + "/mcp") }
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    private func nextAvailablePort(startingAt start: Int, used: Set<Int>, defaultStart: Int) -> Int {
        let clampedStart = min(max(1024, start), 65_535)

        if let candidate = (clampedStart...65_535).first(where: { !used.contains($0) }) {
            return candidate
        }

        if clampedStart > 1024,
           let candidate = (1024..<(clampedStart)).first(where: { !used.contains($0) }) {
            return candidate
        }

        return min(max(1024, defaultStart), 65_535)
    }
}
