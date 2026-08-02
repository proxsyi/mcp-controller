import XCTest
@testable import MCPController

final class PortInspectorTests: XCTestCase {
    func testDoesNotAdoptExecutableNameEmbeddedInAnUnrelatedCommand() {
        var profile = ServerProfile()
        profile.executablePath = "/opt/mcp/server"
        let listener = ListeningProcess(pid: 42, command: "/opt/other/server-helper --listen 3000")

        XCTAssertFalse(PortInspector.belongsToProfile(listener, profile: profile))
    }

    func testDoesNotAdoptAnyProcessUsingAGenericPythonLauncher() {
        var profile = ServerProfile()
        profile.executablePath = "/usr/bin/python3"
        let listener = ListeningProcess(pid: 42, command: "/usr/bin/python3 unrelated_service.py")

        XCTAssertFalse(PortInspector.belongsToProfile(listener, profile: profile))
    }

    func testDistinctiveModuleArgumentCanIdentifyAGenericLauncher() {
        var profile = ServerProfile()
        profile.executablePath = "/usr/bin/python3"
        profile.arguments = ["-m", "mcp_server"]
        let listener = ListeningProcess(pid: 42, command: "/usr/bin/python3 -m mcp_server")

        XCTAssertTrue(PortInspector.belongsToProfile(listener, profile: profile))
    }

    func testExactScriptPathIdentifiesWrappedServerProcess() {
        var profile = ServerProfile()
        profile.executablePath = "/usr/bin/node"
        profile.arguments = ["/Users/cash/servers/desktop-mcp.js"]
        let listener = ListeningProcess(pid: 42, command: "/usr/bin/node /Users/cash/servers/desktop-mcp.js")

        XCTAssertTrue(PortInspector.belongsToProfile(listener, profile: profile))
    }

    func testCommandBasenameIdentifiesNpxCacheExecutable() {
        var profile = ServerProfile()
        profile.executablePath = "/opt/homebrew/bin/npx"
        profile.arguments = [
            "-y",
            "-p",
            "@open-pencil/mcp@0.13.2",
            "openpencil-mcp-http",
            "--streamableHttpPath=/mcp"
        ]
        let listener = ListeningProcess(
            pid: 33_280,
            command: "node /Users/cashm/.npm/_npx/60abe243c92d5e21/node_modules/.bin/openpencil-mcp-http --streamableHttpPath=/mcp"
        )

        XCTAssertTrue(PortInspector.belongsToProfile(listener, profile: profile))
    }
}
