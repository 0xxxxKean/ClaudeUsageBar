#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build_app.sh

DMG_NAME="ClaudeUsageBar.dmg"
STAGING="dist/dmg-staging"

rm -rf "${STAGING}" "dist/${DMG_NAME}"
mkdir -p "${STAGING}"
cp -R "dist/ClaudeUsageBar.app" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create -volname "ClaudeUsageBar" \
  -srcfolder "${STAGING}" \
  -ov -format UDZO \
  "dist/${DMG_NAME}"

echo "Done: dist/${DMG_NAME}"
