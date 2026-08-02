import Foundation

enum RuntimeRecoveryPolicy {
    private static let retryDelays: [TimeInterval] = [1, 2, 4]

    static var maximumAttempts: Int {
        retryDelays.count
    }

    static func retryDelay(
        autoStart: Bool,
        wasUserStopped: Bool,
        attempt: Int
    ) -> TimeInterval? {
        guard autoStart, !wasUserStopped, retryDelays.indices.contains(attempt) else {
            return nil
        }
        return retryDelays[attempt]
    }
}
