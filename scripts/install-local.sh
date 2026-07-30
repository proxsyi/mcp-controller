#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MCP Controller.app"
DEST="/Applications/$APP_NAME"
STAGE="/Applications/.MCP Controller.app.installing"

bash "$ROOT/scripts/build-app.sh"
codesign --verify --deep --strict "$ROOT/dist/$APP_NAME"
rm -rf "$STAGE"
ditto "$ROOT/dist/$APP_NAME" "$STAGE"
rm -rf "$DEST"
mv "$STAGE" "$DEST"
mkdir -p "$HOME/.local/bin"
cp "$DEST/Contents/Resources/mcpctl" "$HOME/.local/bin/mcpctl"
chmod +x "$HOME/.local/bin/mcpctl"
codesign --verify --deep --strict "$DEST"
echo "Installed stable-signed app at $DEST"
