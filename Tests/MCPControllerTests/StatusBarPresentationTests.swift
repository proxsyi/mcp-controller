import XCTest
import AppKit
@testable import MCPController

final class StatusBarPresentationTests: XCTestCase {
    func testRunningServersAppearAsTextBesideTheMenuBarIcon() {
        let presentation = StatusBarPresentation(runningCount: 3, activeCount: 3, failedCount: 0)
        XCTAssertEqual(presentation.title, " 3")
        XCTAssertEqual(presentation.symbolName, "bolt.horizontal.circle.fill")
        XCTAssertEqual(presentation.tooltip, "MCP Controller — 3 running")
    }

    func testTransitionOnlyStateUsesActiveIconWithoutClaimingServersAreRunning() {
        let presentation = StatusBarPresentation(runningCount: 0, activeCount: 2, failedCount: 0)
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.symbolName, "bolt.horizontal.circle.fill")
        XCTAssertEqual(presentation.tooltip, "MCP Controller — 2 starting or stopping")
    }

    func testFailuresAreIncludedWithoutChangingTheRunningCount() {
        let presentation = StatusBarPresentation(runningCount: 1, activeCount: 1, failedCount: 2)
        XCTAssertEqual(presentation.title, " 1")
        XCTAssertEqual(presentation.tooltip, "MCP Controller — 1 running, 2 failed")
    }

    func testStoppedStateHasNoCount() {
        let presentation = StatusBarPresentation(runningCount: 0, activeCount: 0, failedCount: 0)
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.symbolName, "bolt.horizontal.circle")
        XCTAssertEqual(presentation.tooltip, "MCP Controller — no servers running")
    }

    func testPopoverWindowPolicyPreservesNativePopoverWhileJoiningFullScreenSpaces() {
        let behavior = StatusPopoverWindowPolicy.collectionBehavior(
            from: [.moveToActiveSpace, .transient, .ignoresCycle]
        )
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.transient))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertEqual(StatusPopoverWindowPolicy.level, .popUpMenu)
    }
}
