#!/bin/bash
set -euo pipefail

BUNDLE_ID="com.versyi.mcp-controller"
APP_PATH="/Applications/MCP Controller.app"

echo "Resetting macOS privacy permissions for ${BUNDLE_ID}..."
tccutil reset All "${BUNDLE_ID}" || true

# Relaunching makes macOS request any permissions the app actively uses again.
pkill -f "${APP_PATH}/Contents/MacOS/MCPController" || true
sleep 2
open -a "${APP_PATH}"

# macOS does not permit scripts to silently grant TCC permissions. Open the
# relevant panes so the user can approve MCP Controller explicitly.
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo "Permission records reset. Re-enable MCP Controller in Accessibility, Screen & System Audio Recording, and Automation when prompted."
