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
}
