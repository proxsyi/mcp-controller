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
            let clampedStart = min(max(1024, nextGatewayPort), 65_535)
            if let candidate = (clampedStart...65_535).first(where: { !usedPorts.contains($0) }) {
                usedPorts.insert(candidate)
                nextGatewayPort = candidate + 1
                return candidate
            }
            if clampedStart > 1024,
               let candidate = (1024..<(clampedStart)).first(where: { !usedPorts.contains($0) }) {
                usedPorts.insert(candidate)
                nextGatewayPort = candidate + 1
                return candidate
            }
            let fallback = min(max(1024, 39_000), 65_535)
            usedPorts.insert(fallback)
            nextGatewayPort = fallback + 1
            return fallback
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
