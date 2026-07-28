import Foundation

enum GatewayRequestHeaderAdapter {
    static let streamableHTTPAccept = "application/json, text/event-stream"

    static func acceptValue(original: String?, compatibilityEnabled: Bool) -> String? {
        if compatibilityEnabled {
            return streamableHTTPAccept
        }
        return original
    }
}
