import XCTest
@testable import MCPController

final class ServerProfileTests: XCTestCase {
    func testPublicRequestTimeoutDefaultsToFiveMinutes() {
        XCTAssertEqual(ServerProfile().publicRequestTimeoutSeconds, 300)
    }

    func testLegacyProfileDecodesWithFiveMinutePublicTimeout() throws {
        let profile = ServerProfile()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "publicRequestTimeoutSeconds")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ServerProfile.self, from: legacyData)

        XCTAssertEqual(decoded.publicRequestTimeoutSeconds, 300)
    }

    func testPublicRequestTimeoutValidationRange() {
        var profile = ServerProfile()
        profile.executablePath = "/bin/echo"
        profile.exclusiveGatewayEnabled = true
        profile.clientCredentials = [.generate(name: "Test")]
        profile.publicRequestTimeoutSeconds = 29
        XCTAssertTrue(profile.validationErrors().contains { $0.contains("Public request timeout") })
        profile.publicRequestTimeoutSeconds = 300
        XCTAssertFalse(profile.validationErrors().contains { $0.contains("Public request timeout") })
    }

    func testStartupDiagnosticsRedactSecretArgumentsAndEnvironmentValues() {
        var profile = ServerProfile()
        profile.arguments = ["--transport", "http", "--token", "argument-secret", "--api-key=inline-secret"]
        profile.environment = ["API_TOKEN": "environment-secret", "LOG_LEVEL": "debug"]

        let summary = profile.startupDiagnosticSummary

        XCTAssertFalse(summary.contains("argument-secret"))
        XCTAssertFalse(summary.contains("inline-secret"))
        XCTAssertFalse(summary.contains("environment-secret"))
        XCTAssertTrue(summary.contains("--token | <redacted>"))
        XCTAssertTrue(summary.contains("--api-key=<redacted>"))
        XCTAssertTrue(summary.contains("LOG_LEVEL=debug"))
    }

    func testStartupDiagnosticsDescribeEmptyOriginsAsDenied() {
        var profile = ServerProfile()
        profile.allowedOrigins = []
        XCTAssertTrue(profile.startupDiagnosticSummary.contains("Allowed origins: (none; browser origins denied)"))
    }
}
