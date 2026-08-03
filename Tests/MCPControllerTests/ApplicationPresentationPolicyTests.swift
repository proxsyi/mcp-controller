import XCTest
@testable import MCPController

final class ApplicationPresentationPolicyTests: XCTestCase {
    func testVisibleMainWindowUsesRegularActivationPolicy() {
        XCTAssertEqual(
            ApplicationPresentationPolicy.activationPolicy(hasOpenMainWindow: true),
            .regular
        )
    }

    func testMenuBarOnlyStateUsesAccessoryActivationPolicy() {
        XCTAssertEqual(
            ApplicationPresentationPolicy.activationPolicy(hasOpenMainWindow: false),
            .accessory
        )
    }

    func testMainAndPopoverWindowIdentifiersStayDistinct() {
        XCTAssertNotEqual(
            ApplicationPresentationPolicy.mainWindowIdentifier,
            ApplicationPresentationPolicy.statusPopoverWindowIdentifier
        )
        XCTAssertNotEqual(
            ApplicationPresentationPolicy.mainWindowIdentifier,
            ApplicationPresentationPolicy.settingsWindowIdentifier
        )
        XCTAssertNotEqual(
            ApplicationPresentationPolicy.settingsWindowIdentifier,
            ApplicationPresentationPolicy.statusPopoverWindowIdentifier
        )
    }
}
