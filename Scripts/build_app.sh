#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageBar"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"
# A Developer ID Application identity signs with a real, Apple-issued Team ID
# — stable across rebuilds (so macOS keeps remembering "Always Allow" for the
# "Claude Code-credentials" Keychain prompt) and, unlike the old local
# self-signed identity, also notarizable for distribution (see
# Scripts/build_dmg.sh). Falls back to the local self-signed identity from
# Scripts/create_signing_identity.sh if no Developer ID identity is installed,
# for contributors without one.
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
if [ -z "${SIGNING_IDENTITY}" ]; then
    SIGNING_IDENTITY="ClaudeUsageBar Local Signing"
fi

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf dist
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "Generating app icon..."
swift Scripts/generate_app_icon.swift
iconutil -c icns dist/AppIcon.iconset -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.kean.claudeusagebar</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing with '${SIGNING_IDENTITY}'..."
if ! security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
    echo "error: signing identity '${SIGNING_IDENTITY}' not found. Run Scripts/create_signing_identity.sh once first." >&2
    exit 1
fi
# Hardened runtime is required for notarization (Scripts/build_dmg.sh); it's a
# no-op for local-only use since this app does nothing it would restrict.
codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"

echo "Done: ${APP_BUNDLE}"
