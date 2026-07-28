#!/bin/bash
set -euo pipefail

REPO="${HOME}/Projects/Clients/Versyi/MCP-Controller"
cd "${REPO}"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path

gateway = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
text = gateway.read_text()
old = r'''        let endpoint = "\(scheme)://\(host)\(request.target)"'''
new = r'''        let publicTarget = GatewayRouteMapper.publicTarget(
            for: request.target,
            forwardedPrefix: request.headers["x-forwarded-prefix"],
            profile: profile
        )
        let endpoint = "\(scheme)://\(host)\(publicTarget)"'''
if old not in text:
    raise SystemExit("Compatibility endpoint source did not match the expected version")
text = text.replace(old, new, 1)

marker = '''enum GatewayRouteMapper {
    static func upstreamTarget(for requestTarget: String, profile: ServerProfile) -> String {
'''
replacement = '''enum GatewayRouteMapper {
    static func publicTarget(
        for requestTarget: String,
        forwardedPrefix: String? = nil,
        profile: ServerProfile
    ) -> String {
        let pieces = requestTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = pieces.isEmpty ? "/" : String(pieces[0])
        let query = pieces.count > 1 ? "?" + String(pieces[1]) : ""

        if let forwardedPrefix {
            let firstPrefix = forwardedPrefix.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = firstPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
                let normalizedPrefix = prefixed.count > 1 && prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
                if path == "/" { return normalizedPrefix + query }
                if path == normalizedPrefix || path.hasPrefix(normalizedPrefix + "/") { return path + query }
            }
        }

        let mount = profile.normalizedMountPath
        if path == "/" || path == mount { return mount + query }
        return path + query
    }

    static func upstreamTarget(for requestTarget: String, profile: ServerProfile) -> String {
'''
if marker not in text:
    raise SystemExit("GatewayRouteMapper source did not match the expected version")
gateway.write_text(text.replace(marker, replacement, 1))

tests = Path("Tests/MCPControllerTests/GatewayRouteMapperTests.swift")
text = tests.read_text()
addition = '''
    func testCompatibilityRestoresMountAfterProxyStripsPrefix() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"

        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/", profile: profile), "/mcp/remote")
        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/?probe=1", profile: profile), "/mcp/remote?probe=1")
    }

    func testCompatibilityUsesForwardedPrefixWhenAvailable() {
        var profile = ServerProfile()
        profile.mountPath = "/fallback"

        XCTAssertEqual(
            GatewayRouteMapper.publicTarget(for: "/", forwardedPrefix: "/external/mcp/", profile: profile),
            "/external/mcp"
        )
    }

    func testCompatibilityPreservesCanonicalTarget() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/server"

        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/mcp/server", profile: profile), "/mcp/server")
    }
'''
index = text.rfind("\n}")
if index < 0:
    raise SystemExit("GatewayRouteMapperTests closing brace not found")
tests.write_text(text[:index] + addition + text[index:])

changelog = Path("CHANGELOG.md")
text = changelog.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.6.6

### Fixed
- Made compatibility mode reconstruct canonical public endpoints after any path-prefix reverse proxy strips the external mount.
- Added standard `X-Forwarded-Prefix` support with the profile mount path as a safe fallback.
- Preserved query strings and already-canonical paths in compatibility handshakes.
"""
if marker not in text:
    raise SystemExit("CHANGELOG marker missing")
changelog.write_text(text.replace(marker, entry, 1))
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.6.6" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 13" Resources/Info.plist
rm -f .github/workflows/release-v0.6.6.yml

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift \
        Tests/MCPControllerTests/GatewayRouteMapperTests.swift \
        Resources/Info.plist CHANGELOG.md .github/workflows/release-v0.6.6.yml
git commit -m "fix(gateway): preserve public endpoint through proxies"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.6.6 >/dev/null 2>&1; then
    echo "Release v0.6.6 already exists."
else
    gh release create v0.6.6 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.6.6"
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

echo "v0.6.6 installed. Re-enable MCP Controller permissions, enable compatibility mode, and retry the canonical public URL."
