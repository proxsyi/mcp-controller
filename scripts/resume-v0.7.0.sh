#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
text = p.read_text()
old = 'initializeBridge?.requestedVersion ?? "unknown"'
new = 'initializeBridge.requestedVersion'
if old in text:
    p.write_text(text.replace(old, new, 1))
elif new not in text:
    raise SystemExit("Unexpected protocol bridge log expression")
PY

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController Resources/mcpctl Resources/Info.plist scripts/build-app.sh scripts/check-notion-validation.sh CHANGELOG.md
git rm -f scripts/build-v0.7.0-terminal-control.sh scripts/install-v0.7.0.sh scripts/run-v0.7.0.sh scripts/resume-v0.7.0.sh scripts/resume-protocol-version-bridge.sh 2>/dev/null || true
git commit -m "feat: add terminal control and complete compatibility diagnostics"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.7.0 >/dev/null 2>&1; then
  echo "Release v0.7.0 already exists."
else
  gh release create v0.7.0 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.0"
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
echo "v0.7.0 installed. CLI: $HOME/.local/bin/mcpctl"
