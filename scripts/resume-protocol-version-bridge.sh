#!/bin/bash
set -euo pipefail

REPO="$HOME/Projects/Clients/Versyi/MCP-Controller"
cd "$REPO"

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/GatewayInitializeResponseBridge.swift")
if not p.exists():
    raise SystemExit("Partial protocol bridge files are missing; run the original installer first")
text = p.read_text()
old = "final class GatewayInitializeResponseBridge {"
new = "final class GatewayInitializeResponseBridge: @unchecked Sendable {"
if old in text:
    p.write_text(text.replace(old, new, 1))
elif new not in text:
    raise SystemExit("Unexpected GatewayInitializeResponseBridge declaration")
PY

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift \
        Sources/MCPController/Services/GatewayInitializeResponseBridge.swift \
        Tests/MCPControllerTests/GatewayInitializeResponseBridgeTests.swift \
        Resources/Info.plist CHANGELOG.md
git rm -f scripts/apply-protocol-version-bridge.sh
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

echo "v0.6.9 installed. Only /Applications/MCP Controller.app remains. Re-enable permissions and retry Notion."
