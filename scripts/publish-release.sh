#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
TAG="v$VERSION"
TARGET=$(git rev-parse HEAD)

if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  echo "Tracked changes must be committed before publishing." >&2
  exit 1
fi
if [[ $(git rev-list -n 1 "$TAG" 2>/dev/null || true) != "$TARGET" ]]; then
  echo "Tag $TAG must exist and point to full commit $TARGET." >&2
  exit 1
fi

swift test
# build-app.sh performs the strict signature verification before returning.
# Do not re-verify the Finder-visible bundle here: macOS can asynchronously add
# Finder/provenance metadata to the dist directory after signing.
bash scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
(cd dist && shasum -a 256 "MCP-Controller-macOS.zip" > SHA256SUMS.txt)

git push origin main
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists; nothing to publish."
else
  gh release create "$TAG" \
    "dist/MCP-Controller-macOS.zip" \
    "dist/SHA256SUMS.txt" \
    --verify-tag \
    --generate-notes \
    --title "MCP Controller $TAG"
fi

gh release view "$TAG" --json tagName,url,publishedAt
