#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || { echo "usage: $0 APP DMG VOLUME_NAME" >&2; exit 2; }
APP="$1"
DMG="$2"
VOLUME_NAME="$3"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIRECTORY="$(mktemp -d "$PROJECT_ROOT/build/dmg.XXXXXX")"
MOUNT_POINT="$STAGING_DIRECTORY/mount"
IS_MOUNTED=false

cleanup() {
  if [[ "$IS_MOUNTED" == true ]]; then
    hdiutil detach -quiet "$MOUNT_POINT" || true
  fi
  rm -rf "$STAGING_DIRECTORY"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIRECTORY/image/.background" "$MOUNT_POINT"
ditto "$APP" "$STAGING_DIRECTORY/image/Periodic.app"
ln -s /Applications "$STAGING_DIRECTORY/image/Applications"
cp "$PROJECT_ROOT/LICENSE" "$STAGING_DIRECTORY/image/.LICENSE.txt"
xcrun swift "$PROJECT_ROOT/script/dmg_background.swift" \
  "$STAGING_DIRECTORY/image/.background/installer.tiff"
hdiutil create -quiet -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIRECTORY/image" -fs HFS+ -format UDRW \
  "$STAGING_DIRECTORY/layout.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" \
  "$STAGING_DIRECTORY/layout.dmg"
IS_MOUNTED=true

# Finder writes the native icon positions, window bounds, and background alias.
osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run arguments
    set imageFolder to POSIX file (item 1 of arguments) as alias
    tell application "Finder"
        open imageFolder
        set installerWindow to container window of imageFolder
        set current view of installerWindow to icon view
        set toolbar visible of installerWindow to false
        set statusbar visible of installerWindow to false
        set bounds of installerWindow to {200, 200, 1000, 628}
        set options to icon view options of installerWindow
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 16
        set background picture of options to file ".background:installer.tiff" of imageFolder
        set position of item "Periodic.app" of imageFolder to {190, 230}
        set position of item "Applications" of imageFolder to {610, 230}
        close installerWindow
        open imageFolder
        update imageFolder without registering applications
        delay 2
        close container window of imageFolder
    end tell
end run
APPLESCRIPT
[[ -s "$MOUNT_POINT/.DS_Store" ]] || {
  echo "Finder did not save the DMG layout." >&2
  exit 1
}
sync
hdiutil detach -quiet "$MOUNT_POINT"
IS_MOUNTED=false
hdiutil convert -quiet "$STAGING_DIRECTORY/layout.dmg" -format UDZO -ov -o "$DMG"
echo "Drag-to-Applications installer: $DMG"
