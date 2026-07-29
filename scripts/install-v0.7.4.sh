#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/GatewayInitializeResponseBridge.swift")
s = p.read_text()
s = s.replace('''    let upstreamVersion: String?
}
''','''    let upstreamVersion: String?
    let responseComplete: Bool
}
''',1)
s = s.replace('''.init(data: data, sessionID: nil, upstreamVersion: nil)''','''.init(data: data, sessionID: nil, upstreamVersion: nil, responseComplete: false)''')
s = s.replace('''return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream)
''','''return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream, responseComplete: true)
''',1)
s = s.replace('''return resolve(raw.body, sessionID: sessionID(in: headerText), upstream: raw.upstream)
''','''return resolve(raw.body, sessionID: sessionID(in: headerText), upstream: raw.upstream, responseComplete: false)
''',1)
s = s.replace('''return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream)
''','''return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream, responseComplete: true)
''',1)
s = s.replace('''return .init(data: output, sessionID: nil, upstreamVersion: nil)
''','''return .init(data: output, sessionID: nil, upstreamVersion: nil, responseComplete: true)
''',1)
old = '''    private func resolve(_ data: Data, sessionID: String?, upstream: String?) -> GatewayInitializeBridgeOutput {
        resolved = true; buffer.removeAll()
        return .init(data: data, sessionID: sessionID, upstreamVersion: upstream)
    }
'''
new = '''    private func resolve(
        _ data: Data,
        sessionID: String?,
        upstream: String?,
        responseComplete: Bool
    ) -> GatewayInitializeBridgeOutput {
        resolved = true; buffer.removeAll()
        return .init(data: data, sessionID: sessionID, upstreamVersion: upstream, responseComplete: responseComplete)
    }
'''
if old not in s:
    raise SystemExit("Bridge resolve implementation missing")
s = s.replace(old,new,1)
p.write_text(s)

p = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
s = p.read_text()
old = '''            var outgoing: Data?
            if let data, !data.isEmpty {
'''
new = '''            var outgoing: Data?
            var responseComplete = false
            if let data, !data.isEmpty {
'''
if old not in s:
    raise SystemExit("Response completion state insertion point missing")
s = s.replace(old,new,1)
old = '''                    outgoing = result?.data
                    if let sessionID = result?.sessionID, let upstreamVersion = result?.upstreamVersion {
'''
new = '''                    outgoing = result?.data
                    responseComplete = result?.responseComplete == true
                    if let sessionID = result?.sessionID, let upstreamVersion = result?.upstreamVersion {
'''
if old not in s:
    raise SystemExit("Bridge result completion insertion point missing")
s = s.replace(old,new,1)
old = '''            if let outgoing, !outgoing.isEmpty {
                client.send(content: outgoing, completion: .contentProcessed { sendError in
'''
new = '''            let closeAfterResponse = responseComplete
            if let outgoing, !outgoing.isEmpty {
                client.send(content: outgoing, completion: .contentProcessed { sendError in
'''
if old not in s:
    raise SystemExit("Response close capture insertion point missing")
s = s.replace(old,new,1)
old = '''                    } else if isComplete || error != nil {
                        upstream.cancel()
                        client.cancel()
'''
new = '''                    } else if closeAfterResponse || isComplete || error != nil {
                        upstream.cancel()
                        client.cancel()
'''
if old not in s:
    raise SystemExit("Response close decision insertion point missing")
s = s.replace(old,new,1)
p.write_text(s)

c = Path("CHANGELOG.md")
s = c.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.7.4

### Fixed
- Closed the public gateway socket immediately after a complete initialize response was flushed.
- Prevented the next request from entering the brief interval between the HTTP response boundary and the upstream TCP close event.
- Allowed `notifications/initialized` to reach a fresh gateway connection instead of receiving a proxy-generated HTTP 502.
"""
if marker not in s:
    raise SystemExit("CHANGELOG marker missing")
c.write_text(s.replace(marker,entry,1))
PY

cat > Tests/MCPControllerTests/GatewayInitializeResponseCompletionTests.swift <<'SWIFT'
import Foundation
import XCTest
@testable import MCPController

final class GatewayInitializeResponseCompletionTests: XCTestCase {
    func testCompleteChunkedInitializeResponseIsMarkedComplete() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = Data("event: message\r\ndata: {\"result\":{\"protocolVersion\":\"2024-11-05\"}}\r\n\r\n".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: session-1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        response.append(HTTPChunkedBodyEncoder.encode(body))
        response.append(Data("0\r\n\r\n".utf8))

        let result = bridge.consume(response)
        XCTAssertEqual(result?.sessionID, "session-1")
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertEqual(result?.responseComplete, true)
    }
}
SWIFT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.7.4" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 21" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/GatewayInitializeResponseBridge.swift Sources/MCPController/Services/ExclusiveGateway.swift Tests/MCPControllerTests/GatewayInitializeResponseCompletionTests.swift Resources/Info.plist CHANGELOG.md
git rm -f scripts/install-v0.7.4.sh
git commit -m "fix(gateway): close at initialize response boundary"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.7.4 >/dev/null 2>&1; then
  echo "Release v0.7.4 already exists."
else
  gh release create v0.7.4 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.4"
fi

pkill -f '/MCP Controller.app/Contents/MacOS/MCPController' 2>/dev/null || true
sleep 3
rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'
mkdir -p "$HOME/.local/bin"
cp '/Applications/MCP Controller.app/Contents/Resources/mcpctl' "$HOME/.local/bin/mcpctl"
chmod +x "$HOME/.local/bin/mcpctl"
rm -rf 'dist/MCP Controller.app'
rm -f 'dist/MCP-Controller-macOS.zip'
rm -rf "$HOME/Applications/MCP Controller.app"
tccutil reset All com.versyi.mcp-controller || true
open -a '/Applications/MCP Controller.app'
echo "v0.7.4 installed. Start Remote MacOS Use and rerun validation."
