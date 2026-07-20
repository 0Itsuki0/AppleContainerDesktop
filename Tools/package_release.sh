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

# ── 3. Assemble the DMG staging folder ───────────────────────────────────────
log "Staging DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$GUI_SCHEME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$CLI_BIN" "$STAGING_DIR/$CLI_INSTALL_NAME"

# ── 4. Build the DMG (built-in hdiutil, no styling) ──────────────────────────
DMG_NAME="AppleContainerDesktop_${VERSION}.dmg"
DMG_PATH="/tmp/$DMG_NAME"
log "Building $DMG_NAME..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "AppleContainerDesktop" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

# ── 5. Notarize & staple the DMG (covers app + CLI inside it) ─────────────────
log "Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
log "Stapling ticket..."
xcrun stapler staple "$DMG_PATH"

# ── 6. Place outputs on the Desktop ──────────────────────────────────────────
OUT_DIR="$HOME/Desktop/AppleContainerDesktop_${VERSION}"
log "Writing outputs to $OUT_DIR..."
mkdir -p "$OUT_DIR"
mv "$DMG_PATH" "$OUT_DIR/$DMG_NAME"

# install.sh mounts the sibling DMG and installs the CLI to /usr/local/bin.
cat > "$OUT_DIR/install.sh" << 'INSTALL'
#!/bin/bash
#
# install.sh — install the container-desktop CLI from the sibling DMG.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG="$(ls "$SCRIPT_DIR"/*.dmg 2>/dev/null | head -1)"
BIN_NAME="container-desktop"
BINDIR="/usr/local/bin"

if [ -z "$DMG" ]; then
  echo "No .dmg found next to install.sh." >&2
  exit 1
fi

MNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT

echo "Installing $BIN_NAME to $BINDIR (may require your password)..."
sudo install -d "$BINDIR"
sudo install "$MNT/$BIN_NAME" "$BINDIR/$BIN_NAME"

echo "Installed: $BINDIR/$BIN_NAME"
INSTALL
chmod +x "$OUT_DIR/install.sh"

# ── 7. Cleanup ────────────────────────────────────────────────────────────────
rm -rf "$STAGING_DIR" "$ARCHIVE_PATH" "$EXPORT_PATH"

log "Done. Packaged v${VERSION} (${BUILD}) → $OUT_DIR"
