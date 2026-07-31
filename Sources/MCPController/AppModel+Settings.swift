import Foundation

extension AppModel {
    func applyGlobalOneAIPolicy(_ enabled: Bool) {
        let serverProfiles = profiles.filter(\.isServer)
        var usedPorts = Set(serverProfiles.map(\.localPort))
        var preservedGatewayPorts: [UUID: Int] = [:]

        if enabled {
            for profile in serverProfiles {
                let port = profile.gatewayPort
                guard (1024...65_535).contains(port),
                      port != profile.localPort,
                      !usedPorts.contains(port) else {
                    continue
                }
                preservedGatewayPorts[profile.id] = port
                usedPorts.insert(port)
            }
        }

        var nextGatewayPort = 39_000
        func allocateGatewayPort() -> Int {
            while usedPorts.contains(nextGatewayPort) { nextGatewayPort += 1 }
            let port = nextGatewayPort
            usedPorts.insert(port)
            nextGatewayPort += 1
            return port
        }

        for original in profiles {
            guard original.isServer else { continue }
            var profile = original
            profile.exclusiveGatewayEnabled = enabled

            if enabled {
                if profile.clientCredentials.isEmpty {
                    profile.clientCredentials = [.generate(name: "Primary AI")]
                }
                profile.gatewayPort = preservedGatewayPorts[profile.id] ?? allocateGatewayPort()
            }

            if profile != original { update(profile) }
        }
    }
}
