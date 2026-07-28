#!/bin/bash
set -euo pipefail

REPO="${HOME}/Projects/Clients/Versyi/MCP-Controller"
cd "${REPO}"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path

gateway = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
text = gateway.read_text()
old = '''            guard !["authorization", "host", "connection", "content-length", "transfer-encoding", "origin", "x-forwarded-host", "x-forwarded-proto"].contains(name) else { continue }
            headers += "\\(name): \\(value)\\r\\n"
        }
        headers += "User-Agent: MCP Controller\\r\\n"
'''
new = '''            guard !["accept", "authorization", "host", "connection", "content-length", "transfer-encoding", "origin", "x-forwarded-host", "x-forwarded-proto"].contains(name) else { continue }
            headers += "\\(name): \\(value)\\r\\n"
        }
        if let accept = GatewayRequestHeaderAdapter.acceptValue(
            original: request.headers["accept"],
            compatibilityEnabled: profile.remoteClientCompatibilityEnabled
        ) {
            headers += "Accept: \\(accept)\\r\\n"
        }
        headers += "User-Agent: MCP Controller\\r\\n"
'''
if old not in text:
    raise SystemExit("ExclusiveGateway upstream header source did not match the expected version")
gateway.write_text(text.replace(old, new, 1))

changelog = Path("CHANGELOG.md")
text = changelog.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.6.7

### Fixed
- Made compatibility mode normalize outbound MCP `Accept` headers to include both `application/json` and `text/event-stream`.
- Adapted strict remote clients without changing upstream MCP servers or weakening strict mode when compatibility is off.
"""
if marker not in text:
    raise SystemExit("CHANGELOG marker missing")
changelog.write_text(text.replace(marker, entry, 1))
PY

cat > Sources/MCPController/Services/GatewayRequestHeaderAdapter.swift <<'SWIFT'
import Foundation

enum GatewayRequestHeaderAdapter {
    static let streamableHTTPAccept = "application/json, text/event-stream"

    static func acceptValue(original: String?, compatibilityEnabled: Bool) -> String? {
        if compatibilityEnabled {
            return streamableHTTPAccept
        }
        return original
    }
}
SWIFT

cat > Tests/MCPControllerTests/GatewayRequestHeaderAdapterTests.swift <<'SWIFT'
import XCTest
@testable import MCPController

final class GatewayRequestHeaderAdapterTests: XCTestCase {
    func testCompatibilitySuppliesBothRequiredMediaTypes() {
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "application/json", compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "text/event-stream", compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: nil, compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
    }

    func testStrictModePreservesClientHeader() {
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "application/json", compatibilityEnabled: false),
            "application/json"
        )
        XCTAssertNil(GatewayRequestHeaderAdapter.acceptValue(original: nil, compatibilityEnabled: false))
    }
}
SWIFT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.6.7" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 14" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift \
        Sources/MCPController/Services/GatewayRequestHeaderAdapter.swift \
        Tests/MCPControllerTests/GatewayRequestHeaderAdapterTests.swift \
        Resources/Info.plist CHANGELOG.md
git commit -m "fix(gateway): normalize Accept in compatibility mode"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.6.7 >/dev/null 2>&1; then
    echo "Release v0.6.7 already exists."
else
    gh release create v0.6.7 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.6.7"
fi

rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'

tccutil reset All com.versyi.mcp-controller || true
pkill -f '/Applications/MCP Controller.app/Contents/MacOS/MCPController' || true
sleep 3
open -a '/Applications/MCP Controller.app'
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo "v0.6.7 installed. Re-enable permissions, enable compatibility mode, start the server, and retry Notion."
