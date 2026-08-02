import Foundation

enum GatewayOptionalDiscoveryFallback {
    static let initializedSessionMarker = "__mcp_controller_initialized_session__"

    static func emptyResult(
        for method: String,
        upstreamCapabilities: Set<String>
    ) -> [String: Any]? {
        guard upstreamCapabilities.contains(initializedSessionMarker) else { return nil }
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
