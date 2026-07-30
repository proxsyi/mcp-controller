import Foundation

enum GatewayOptionalDiscoveryFallback {
    static func emptyResult(
        for method: String,
        upstreamCapabilities: Set<String>
    ) -> [String: Any]? {
        switch method {
        case "resources/templates/list":
            guard !upstreamCapabilities.contains("resources") else { return nil }
            return ["resourceTemplates": []]
        case "resources/list":
            guard !upstreamCapabilities.contains("resources") else { return nil }
            return ["resources": []]
        case "prompts/list":
            guard !upstreamCapabilities.contains("prompts") else { return nil }
            return ["prompts": []]
        default:
            return nil
        }
    }
}
