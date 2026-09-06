#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP_DIR="$ROOT/dist/MCP Controller.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp -X "$ROOT/.build/release/MCPController" "$CONTENTS/MacOS/MCPController"
cp -X "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp -X "$ROOT/Resources/mcpctl" "$CONTENTS/Resources/mcpctl"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp -X "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi
chmod +x "$CONTENTS/MacOS/MCPController" "$CONTENTS/Resources/mcpctl"
# Finder/provenance metadata can be copied from local app bundles and makes codesign reject the build.
xattr -cr "$APP_DIR" 2>/dev/null || true

SIGNING_IDENTITY="${MCP_CONTROLLER_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"MCP Controller Local Signing"'; then
  SIGNING_IDENTITY="MCP Controller Local Signing"
elif [[ -z "$SIGNING_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Session Pinger Signing"'; then
  # Stable local fallback already present in this user's login keychain.
  SIGNING_IDENTITY="Session Pinger Signing"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
  echo "Signed with stable identity: $SIGNING_IDENTITY"
else
  echo "Warning: no stable signing identity found; app was left unsigned." >&2
  echo "Set MCP_CONTROLLER_SIGNING_IDENTITY before installing this build." >&2
fi

echo "Built $APP_DIR"
