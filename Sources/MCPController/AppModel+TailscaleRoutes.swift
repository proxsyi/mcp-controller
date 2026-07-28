import Foundation

extension AppModel {
    @discardableResult
    func startTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard phase(for: profile.id) == .running else {
            presentedError = "Start \(profile.name) before enabling its Tailscale route."
            return false
        }
        var configured = profile
        configured.tailscaleRouteEnabled = true
        guard let arguments = TailscaleCommandBuilder.enableArguments(for: configured) else {
            presentedError = "Choose Tailnet or Public Funnel before starting the route."
            return false
        }
        do {
            let result = try CommandRunner.run(executable: configured.tailscalePath, arguments: arguments)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            update(configured)
            return true
        } catch {
            presentedError = "Could not start the Tailscale route for \(profile.name): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func stopTailscaleRoute(_ profile: ServerProfile) -> Bool {
        guard let arguments = TailscaleCommandBuilder.disableArguments(for: profile) else { return true }
        do {
            let result = try CommandRunner.run(executable: profile.tailscalePath, arguments: arguments)
            guard result.exitCode == 0 else { throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error) }
            var configured = profile
            configured.tailscaleRouteEnabled = false
            update(configured)
            return true
        } catch {
            presentedError = "Could not stop the Tailscale route for \(profile.name): \(error.localizedDescription)"
            return false
        }
    }
}
