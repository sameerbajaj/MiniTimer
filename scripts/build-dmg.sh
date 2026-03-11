#!/bin/bash
set -e

APP_NAME="MiniTimer"
VERSION=${1:-"1.0.0"}
STAGING_DIR="build/staging"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# 1. Build
echo "Building ${APP_NAME} v${VERSION}..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           MARKETING_VERSION="${VERSION}" \
           CLEAN_BEFORE_BUILD=YES \
           CODE_SIGNING_ALLOWED=NO \
           build

# Find the built .app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -type d -print -quit)
if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built .app"
    exit 1
fi

# 2. Inject Icon if missing (Simplified for this project)
if [ ! -f "${APP_PATH}/Contents/Resources/AppIcon.icns" ]; then
    echo "Generating icons..."
    swift scripts/generate-icon.swift
    mkdir -p AppIcon.iconset
    sips -z 16 16   AppIcon.png --out AppIcon.iconset/icon_16x16.png
    sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
    sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_32x32.png
    sips -z 64 64   AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
    sips -z 128 128 AppIcon.png --out AppIcon.iconset/icon_128x128.png
    sips -z 256 256 AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
    sips -z 256 256 AppIcon.iconset/icon_256x256.png
    sips -z 512 512 AppIcon.iconset/icon_256x256@2x.png
    sips -z 512 512 AppIcon.iconset/icon_512x512.png
    sips -z 1024 1024 AppIcon.iconset/icon_512x512@2x.png
    iconutil -c icns AppIcon.iconset
    cp AppIcon.icns "${APP_PATH}/Contents/Resources/AppIcon.icns"
    rm -rf AppIcon.iconset AppIcon.png AppIcon.icns
fi

# 3. Ad-hoc codesign
echo "Ad-hoc signing..."
codesign --force --deep --sign - "${APP_PATH}"

# 4. Create DMG
echo "Packaging DMG..."
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}"

# Cleanup
rm -rf "${STAGING_DIR}"
echo "Build complete: ${DMG_NAME}"
