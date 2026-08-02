import Foundation

enum ApplicationLifetimePolicy {
    static let automaticTerminationReason = "MCP services must remain available"

    static func keepControllerAvailable(
        disableAutomaticTermination: (String) -> Void = ProcessInfo.processInfo.disableAutomaticTermination
    ) {
        disableAutomaticTermination(automaticTerminationReason)
    }
}
