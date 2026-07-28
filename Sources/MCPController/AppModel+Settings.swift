import Foundation

extension AppModel {
    func applyGlobalOneAIPolicy(_ enabled: Bool) {
        var nextGatewayPort = 39_000
        var usedPorts = Set(profiles.map(\.localPort))

        for original in profiles {
            var profile = original
            profile.exclusiveGatewayEnabled = enabled

            if enabled {
                if profile.clientCredentials.isEmpty {
                    profile.clientCredentials = [.generate(name: "Primary AI")]
                }
                while usedPorts.contains(nextGatewayPort) { nextGatewayPort += 1 }
                profile.gatewayPort = nextGatewayPort
                usedPorts.insert(nextGatewayPort)
                nextGatewayPort += 1
            }

            if profile != original { update(profile) }
        }
    }
}
