#!/bin/bash
set -euo pipefail

REPO="$HOME/Projects/Clients/Versyi/MCP-Controller"
cd "$REPO"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path
p=Path('Sources/MCPController/Services/ExclusiveGateway.swift')
s=p.read_text()

s=s.replace('''    private var arbiter: ExclusiveLeaseArbiter
''','''    private var arbiter: ExclusiveLeaseArbiter
    private var bridgedProtocolVersions: [String: String] = [:]
''',1)

old='''        let target = GatewayRouteMapper.upstreamTarget(for: request.target, profile: profile)
        let upstream = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
'''
new='''        let target = GatewayRouteMapper.upstreamTarget(for: request.target, profile: profile)
        let responseBridge: GatewayInitializeResponseBridge?
        if profile.remoteClientCompatibilityEnabled, let requestedVersion = request.requestedProtocolVersion {
            responseBridge = GatewayInitializeResponseBridge(requestedVersion: requestedVersion)
        } else {
            responseBridge = nil
        }
        let upstream = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
'''
if old not in s: raise SystemExit('proxy bridge insertion point missing')
s=s.replace(old,new,1)
s=s.replace('''                        self.pipeUpstreamResponse(upstream, to: connection)
''','''                        self.pipeUpstreamResponse(upstream, to: connection, initializeBridge: responseBridge)
''',1)

old='''            guard !["accept", "authorization", "host", "connection", "content-length", "transfer-encoding", "origin", "x-forwarded-host", "x-forwarded-proto"].contains(name) else { continue }
            headers += "\\(name): \\(value)\\r\\n"
        }
        if let accept = GatewayRequestHeaderAdapter.acceptValue(
'''
new='''            guard !["accept", "authorization", "host", "connection", "content-length", "transfer-encoding", "origin", "mcp-protocol-version", "x-forwarded-host", "x-forwarded-proto"].contains(name) else { continue }
            headers += "\\(name): \\(value)\\r\\n"
        }
        var protocolVersion = request.headers["mcp-protocol-version"]
        if profile.remoteClientCompatibilityEnabled,
           let sessionID = request.headers["mcp-session-id"],
           let bridgedVersion = bridgedProtocolVersions[sessionID] {
            protocolVersion = bridgedVersion
        }
        if let protocolVersion {
            headers += "MCP-Protocol-Version: \\(protocolVersion)\\r\\n"
        }
        if let accept = GatewayRequestHeaderAdapter.acceptValue(
'''
if old not in s: raise SystemExit('header bridge insertion point missing')
s=s.replace(old,new,1)

start=s.index('    private func pipeUpstreamResponse(')
end=s.index('    private func sendError(', start)
new_func='''    private func pipeUpstreamResponse(
        _ upstream: NWConnection,
        to client: NWConnection,
        initializeBridge: GatewayInitializeResponseBridge? = nil
    ) {
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                upstream.cancel()
                client.cancel()
                return
            }

            var outgoing: Data?
            if let data, !data.isEmpty {
                if let initializeBridge {
                    let result = initializeBridge.consume(data, isFinal: isComplete || error != nil)
                    outgoing = result?.data
                    if let sessionID = result?.sessionID, let upstreamVersion = result?.upstreamVersion {
                        self.bridgedProtocolVersions[sessionID] = upstreamVersion
                    }
                } else {
                    outgoing = data
                }
            } else if let initializeBridge, isComplete || error != nil {
                outgoing = initializeBridge.finish()?.data
            }

            if let outgoing, !outgoing.isEmpty {
                client.send(content: outgoing, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        upstream.cancel()
                        client.cancel()
                    } else if isComplete || error != nil {
                        upstream.cancel()
                        client.cancel()
                    } else {
                        self.pipeUpstreamResponse(upstream, to: client, initializeBridge: initializeBridge)
                    }
                })
            } else if isComplete || error != nil {
                upstream.cancel()
                client.cancel()
            } else {
                self.pipeUpstreamResponse(upstream, to: client, initializeBridge: initializeBridge)
            }
        }
    }

'''
s=s[:start]+new_func+s[end:]

old='''    var jsonRPCID: Any {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return NSNull() }
        return object["id"] ?? NSNull()
    }
'''
new='''    var jsonRPCID: Any {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return NSNull() }
        return object["id"] ?? NSNull()
    }

    var requestedProtocolVersion: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] as? String == "initialize",
              let params = object["params"] as? [String: Any] else { return nil }
        return params["protocolVersion"] as? String
    }
'''
if old not in s: raise SystemExit('request protocol property insertion missing')
s=s.replace(old,new,1)
p.write_text(s)

c=Path('CHANGELOG.md')
s=c.read_text(); marker='## Unreleased\n'
entry='''## Unreleased

## v0.6.9

### Fixed
- Added a generic per-session MCP protocol bridge for compatibility mode.
- Preserved the upstream protocol version internally while presenting the client-requested dated protocol version to strict hosted clients.
- Rewrote subsequent `MCP-Protocol-Version` headers back to each session’s negotiated upstream version.
'''
if marker not in s: raise SystemExit('changelog marker missing')
c.write_text(s.replace(marker,entry,1))
PY

cat > Sources/MCPController/Services/GatewayInitializeResponseBridge.swift <<'SWIFT'
import Foundation

struct GatewayInitializeBridgeOutput {
    let data: Data
    let sessionID: String?
    let upstreamVersion: String?
}

final class GatewayInitializeResponseBridge {
    private let requestedVersion: String
    private var buffer = Data()
    private var resolved = false

    init(requestedVersion: String) {
        self.requestedVersion = requestedVersion
    }

    func consume(_ data: Data, isFinal: Bool = false) -> GatewayInitializeBridgeOutput? {
        if resolved { return GatewayInitializeBridgeOutput(data: data, sessionID: nil, upstreamVersion: nil) }
        buffer.append(data)

        let prefix = Data("\"protocolVersion\":\"".utf8)
        guard let versionPrefix = buffer.range(of: prefix) else {
            if isFinal || buffer.count > 1_048_576 { return finish() }
            return nil
        }
        let versionStart = versionPrefix.upperBound
        guard let quote = buffer[versionStart...].firstIndex(of: UInt8(ascii: "\"")) else {
            if isFinal { return finish() }
            return nil
        }
        let upstreamVersion = String(data: buffer[versionStart..<quote], encoding: .utf8)
        let sessionID = Self.sessionID(in: buffer)

        if let upstreamVersion, requestedVersion.utf8.count == upstreamVersion.utf8.count {
            buffer.replaceSubrange(versionStart..<quote, with: requestedVersion.utf8)
        }
        resolved = true
        let output = buffer
        buffer.removeAll(keepingCapacity: false)
        return GatewayInitializeBridgeOutput(data: output, sessionID: sessionID, upstreamVersion: upstreamVersion)
    }

    func finish() -> GatewayInitializeBridgeOutput? {
        guard !buffer.isEmpty else { return nil }
        resolved = true
        let output = buffer
        buffer.removeAll(keepingCapacity: false)
        return GatewayInitializeBridgeOutput(data: output, sessionID: nil, upstreamVersion: nil)
    }

    private static func sessionID(in response: Data) -> String? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = response.range(of: separator),
              let headerText = String(data: response[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name == "mcp-session-id" {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
SWIFT

cat > Tests/MCPControllerTests/GatewayInitializeResponseBridgeTests.swift <<'SWIFT'
import Foundation
import XCTest
@testable import MCPController

final class GatewayInitializeResponseBridgeTests: XCTestCase {
    func testRewritesClientFacingVersionAndCapturesUpstreamSession() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let response = Data(("HTTP/1.1 200 OK\r\nMcp-Session-Id: abc-123\r\nTransfer-Encoding: chunked\r\n\r\n" +
            "data: {\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2024-11-05\"}}\r\n\r\n").utf8)
        let result = bridge.consume(response)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.sessionID, "abc-123")
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"protocolVersion\":\"2025-11-25\""))
    }

    func testHandlesVersionMarkerSplitAcrossPackets() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        XCTAssertNil(bridge.consume(Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: s\r\n\r\ndata: {\"protocol".utf8)))
        let result = bridge.consume(Data("Version\":\"2024-11-05\"}\r\n\r\n".utf8))
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("2025-11-25"))
    }

    func testPassesThroughAfterInitialRewrite() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        _ = bridge.consume(Data("HTTP/1.1 200 OK\r\n\r\n{\"protocolVersion\":\"2024-11-05\"}".utf8))
        let later = Data("later".utf8)
        XCTAssertEqual(bridge.consume(later)?.data, later)
    }
}
SWIFT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.6.9" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 16" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift \
        Sources/MCPController/Services/GatewayInitializeResponseBridge.swift \
        Tests/MCPControllerTests/GatewayInitializeResponseBridgeTests.swift \
        Resources/Info.plist CHANGELOG.md
git commit -m "fix(gateway): bridge MCP protocol versions per session"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.6.9 >/dev/null 2>&1; then
  echo "Release v0.6.9 already exists."
else
  gh release create v0.6.9 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.6.9"
fi

pkill -f '/MCP Controller.app/Contents/MacOS/MCPController' 2>/dev/null || true
sleep 3
rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'
rm -rf 'dist/MCP Controller.app'
rm -f 'dist/MCP-Controller-macOS.zip'
rm -rf "$HOME/Applications/MCP Controller.app"
tccutil reset All com.versyi.mcp-controller || true
open -a '/Applications/MCP Controller.app'
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo "v0.6.9 installed. Re-enable permissions, start Remote macOS Use with compatibility mode on, and retry Notion."
