import Foundation

enum TailscaleCommandBuilder {
    static func enableArguments(for profile: ServerProfile) -> [String]? {
        guard profile.tailscaleRouteEnabled else { return nil }
        let target = "http://127.0.0.1:\(profile.exposedLocalPort)"
        switch profile.exposureMode {
        case .disabled: return nil
        case .tailnet: return ["serve", "--bg", "--https=\(profile.publicPort)", "--set-path=\(profile.normalizedMountPath)", target]
        case .funnel: return ["funnel", "--bg", "--https=\(profile.publicPort)", "--set-path=\(profile.normalizedMountPath)", target]
        }
    }

    static func removeArguments(for profile: ServerProfile) -> [String]? {
        switch profile.exposureMode {
        case .disabled: return nil
        case .tailnet: return ["serve", "--https=\(profile.publicPort)", "--set-path=\(profile.normalizedMountPath)", "off"]
        case .funnel: return ["funnel", "--https=\(profile.publicPort)", "--set-path=\(profile.normalizedMountPath)", "off"]
        }
    }

    static func disableArguments(for profile: ServerProfile) -> [String]? {
        nil
    }
}
