#!/bin/bash
#
# package_release.sh — Build, sign, notarize, and package a new
# AppleContainerDesktop release: a DMG (GUI app + CLI binary) and an install.sh
# for the CLI. Output goes to ~/Desktop/AppleContainerDesktop_<version>/.
#
# Prerequisites:
# Run the following command to add /update A "Developer ID Application" certificate in the keychain.
#
#   xcrun notarytool store-credentials "notarytool-profile" \
#     --apple-id "your@apple.id" --team-id "NLTYK5T6U3" \
#     --password "<app-specific-password>"
#
#  - Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com) → Security → App-Specific Passwords
#
#
#
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# This project's packages require the Swift 6.4 toolchain (Xcode 27 / beta).
# Plain xcodebuild (Xcode 26.x, Swift 6.3.3) fails package resolution.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

GUI_SCHEME="AppleContainerDesktop"
CLI_SCHEME="ContainerDesktopCommand"
CLI_PRODUCT="ContainerDesktopCommand"   # built binary name
CLI_INSTALL_NAME="container-desktop"     # name once installed on PATH
NOTARYTOOL_PROFILE="notarytool-profile"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/AppleContainerDesktop.xcodeproj"
ARCHIVE_PATH="/tmp/AppleContainerDesktop.xcarchive"
EXPORT_PATH="/tmp/AppleContainerDesktopExport"
STAGING_DIR="/tmp/AppleContainerDesktopDMG"
# ─────────────────────────────────────────────────────────────────────────────

log() { echo "▶ $*"; }

# ── 0. Team id (used for signing during export) ───────────────────────────────
TEAM_ID=$(grep -m1 'DEVELOPMENT_TEAM' "$PROJECT/project.pbxproj" \
  | awk -F'= ' '{ gsub(/;/, "", $2); print $2 }' | tr -d ' ')

# ── 1. Archive & export the GUI (Developer ID) ────────────────────────────────
log "Archiving $GUI_SCHEME..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$GUI_SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates

log "Exporting archive..."
cat > /tmp/ExportOptions.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/$GUI_SCHEME.app"
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
BUILD=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)
log "Version: $VERSION ($BUILD)"

# ── 2. Build the CLI (signed by Xcode during the build) ──────────────────────
log "Building $CLI_SCHEME..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$CLI_SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates

CLI_BUILD_DIR=$(xcodebuild \
  -project "$PROJECT" -scheme "$CLI_SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
CLI_BIN="$CLI_BUILD_DIR/$CLI_PRODUCT"

# ── 3. Notarize & staple the app (the CLI is not notarized) ──────────────────
log "Notarizing app..."
APP_ZIP="/tmp/AppleContainerDesktop-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
log "Stapling ticket..."
xcrun stapler staple "$APP_PATH"
rm -f "$APP_ZIP"

# ── 4. Assemble the DMG staging folder (app + CLI + install.sh) ──────────────
log "Staging DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$GUI_SCHEME.app"
cp "$CLI_BIN" "$STAGING_DIR/$CLI_INSTALL_NAME"

# install.sh installs the CLI sitting next to it on the mounted volume.
cat > "$STAGING_DIR/install.sh" << 'INSTALL'
#!/bin/bash
#
# install.sh — install the container-desktop CLI to /usr/local/bin.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_NAME="container-desktop"
BINDIR="/usr/local/bin"

echo "Installing $BIN_NAME to $BINDIR (may require your password)..."
sudo install -d "$BINDIR"
sudo install "$SCRIPT_DIR/$BIN_NAME" "$BINDIR/$BIN_NAME"
# The CLI is not notarized; clear quarantine so it runs without Gatekeeper prompts.
sudo xattr -d com.apple.quarantine "$BINDIR/$BIN_NAME" 2>/dev/null || true

echo "Installed: $BINDIR/$BIN_NAME"
INSTALL
chmod +x "$STAGING_DIR/install.sh"

# ── 5. Build the DMG (built-in hdiutil, no styling) ──────────────────────────
DMG_NAME="AppleContainerDesktop_${VERSION}.dmg"
DMG_PATH="/tmp/$DMG_NAME"
log "Building $DMG_NAME..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "AppleContainerDesktop" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

# ── 6. Place the DMG on the Desktop ──────────────────────────────────────────
DMG_DEST="$HOME/Desktop/$DMG_NAME"
log "Writing $DMG_DEST..."
mv "$DMG_PATH" "$DMG_DEST"

# ── 7. Cleanup ────────────────────────────────────────────────────────────────
rm -rf "$STAGING_DIR" "$ARCHIVE_PATH" "$EXPORT_PATH"

log "Done. Packaged v${VERSION} (${BUILD}) → $DMG_DEST"
