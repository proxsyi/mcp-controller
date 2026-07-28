#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP_DIR="$ROOT/dist/MCP Controller.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/MCPController" "$CONTENTS/MacOS/MCPController"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/MCPController"

echo "Built $APP_DIR"
