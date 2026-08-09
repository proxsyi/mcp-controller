import Foundation

extension AppModel {
    func shutdownForApplicationQuit() async {
        stopAutoReleaseAllLoop()
        stopImmediatelyForApplicationQuit()
        let funnelProfiles = serverProfiles.filter { $0.tailscaleRouteEnabled && $0.exposureMode == .funnel }

        await withTaskGroup(of: Void.self) { group in
            for profile in funnelProfiles {
                group.addTask {
                    guard TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath) else { return }
                    for arguments in TailscaleCommandBuilder.allManagedRemoveArgumentSets(for: profile) {
                        _ = try? await CommandRunner.runAsync(
                            executable: profile.tailscalePath,
                            arguments: arguments,
                            timeout: 2
                        )
                    }
                }
            }
        }

        tailscaleFunnelRunning = false
        UserDefaults.standard.set(false, forKey: "tailscale.funnelRunning")
    }
}
