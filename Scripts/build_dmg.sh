#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build_app.sh

DMG_NAME="ClaudeUsageBar.dmg"
STAGING="dist/dmg-staging"
# Profile name saved by: xcrun notarytool store-credentials "ClaudeUsageBar-Notarize" ...
NOTARY_PROFILE="ClaudeUsageBar-Notarize"

rm -rf "${STAGING}" "dist/${DMG_NAME}"
mkdir -p "${STAGING}"
cp -R "dist/ClaudeUsageBar.app" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create -volname "ClaudeUsageBar" \
  -srcfolder "${STAGING}" \
  -ov -format UDZO \
  "dist/${DMG_NAME}"

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Submitting dist/${DMG_NAME} for notarization (calls out to Apple, can take a few minutes)..."
    xcrun notarytool submit "dist/${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "dist/${DMG_NAME}"
else
    echo "warning: no Developer ID Application identity installed — skipping notarization. This .dmg will trigger Gatekeeper's 'damaged' warning on other machines; see README." >&2
fi

echo "Done: dist/${DMG_NAME}"
