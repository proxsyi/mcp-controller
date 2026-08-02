import XCTest
@testable import MCPController

final class CommandRunnerTests: XCTestCase {
    func testCapturesStandardOutputAndErrorWithoutDeadlocking() throws {
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf output; printf error >&2"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "output")
        XCTAssertEqual(result.error, "error")
    }

    func testTimeoutDoesNotWaitForDescendantThatKeepsPipesOpen() {
        let started = Date()

        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 2 & wait"],
                timeout: 0.05
            )
        ) { error in
            guard case CommandRunnerError.timedOut = error else {
                return XCTFail("Expected a timeout, got \(error)")
            }
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.75)
    }
}
