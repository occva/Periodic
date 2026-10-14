#!/usr/bin/env bash
set -euo pipefail

MODE="package"
IS_NOTARIZED=true
for argument in "$@"; do
  case "$argument" in
    --local)
      [[ "$MODE" != "--publish" ]] || { echo "--local cannot publish." >&2; exit 2; }
      MODE="--local"; IS_NOTARIZED=false
      ;;
    --publish)
      [[ "$MODE" != "--local" ]] || { echo "--local cannot publish." >&2; exit 2; }
      MODE="--publish"
      ;;
    --unnotarized) IS_NOTARIZED=false ;;
    *) echo "usage: $0 [--local|--publish] [--unnotarized]" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
VERSION="$(awk '/^MARKETING_VERSION = / { print $3 }' Configurations/Base.xcconfig)"
BUILD_NUMBER="$(awk '/^CURRENT_PROJECT_VERSION = / { print $3 }' Configurations/Base.xcconfig)"
PUBLIC_KEY="$(awk '/^SPARKLE_PUBLIC_ED_KEY = / { print $3 }' Configurations/Updates.xcconfig)"
KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-Periodic}"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
TEAM_ID="${APPLE_TEAM_ID:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"

fail() { echo "$*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid marketing version."
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "Build number must be a positive integer."
[[ -n "$PUBLIC_KEY" ]] || fail "Missing Sparkle public key in Configurations/Updates.xcconfig."

if [[ "$IS_NOTARIZED" == true ]]; then
  [[ -n "$SIGNING_IDENTITY" && -n "$TEAM_ID" && -n "$NOTARY_PROFILE" ]] ||
    fail "Notarized packaging requires DEVELOPER_ID_APPLICATION, APPLE_TEAM_ID and NOTARYTOOL_PROFILE. Use --unnotarized for distribution without Apple notarization, or --local for validation only."
  [[ "$SIGNING_IDENTITY" == "Developer ID Application: "* ]] ||
    fail "Use a Developer ID Application identity for distribution."
  security find-identity -v -p codesigning | /usr/bin/grep -F "\"$SIGNING_IDENTITY\"" >/dev/null ||
    fail "Developer ID Application signing identity is not installed."
fi
if [[ "$MODE" != "--local" ]]; then
  [[ -z "$(git status --porcelain)" ]] ||
    fail "Public release packages require a clean committed worktree."
  [[ -f "docs/releases/$VERSION.md" ]] || fail "Missing release notes for $VERSION."
  if [[ "$IS_NOTARIZED" == false ]]; then
    /usr/bin/grep -F "未经 Apple 公证" "docs/releases/$VERSION.md" >/dev/null ||
      fail "Release notes must identify an unnotarized distribution."
  fi
fi

COMMIT="$(git rev-parse HEAD)"
if [[ "$MODE" == "--publish" ]]; then
  REMOTE_COMMIT="$(git ls-remote origin refs/heads/main | awk '{ print $1 }')"
  [[ "$COMMIT" == "$REMOTE_COMMIT" ]] ||
    fail "Publish only from the exact commit already pushed to origin/main."
  if gh release view "v$VERSION" --repo occva/Periodic >/dev/null 2>&1; then
    fail "Release v$VERSION already exists; do not overwrite published artifacts."
  fi
fi

SUFFIX=""
if [[ "$MODE" == "--local" ]]; then SUFFIX="-local"; fi
OUTPUT_DIRECTORY="$PROJECT_ROOT/dist/$VERSION$SUFFIX"
mkdir -p "$PROJECT_ROOT/build" "$OUTPUT_DIRECTORY"
STAGING_DIRECTORY="$(mktemp -d "$PROJECT_ROOT/build/release.XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
DMG="$OUTPUT_DIRECTORY/Periodic-$VERSION$SUFFIX.dmg"
ARCHIVE="$STAGING_DIRECTORY/Periodic.xcarchive"

XCODE_OPTIONS=(
  -quiet -project Periodic.xcodeproj -scheme Periodic -configuration Release
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED_DATA"
  -disableAutomaticPackageResolution
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
)

if [[ "$IS_NOTARIZED" == false ]]; then
  xcodebuild "${XCODE_OPTIONS[@]}" CODE_SIGN_IDENTITY=- build
  APP="$DERIVED_DATA/Build/Products/Release/Periodic.app"
else
  xcodebuild "${XCODE_OPTIONS[@]}" \
    "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" "DEVELOPMENT_TEAM=$TEAM_ID" \
    -archivePath "$ARCHIVE" archive
  python3 - "$STAGING_DIRECTORY/ExportOptions.plist" "$TEAM_ID" "$SIGNING_IDENTITY" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "method": "developer-id",
        "signingStyle": "manual",
        "teamID": sys.argv[2],
        "signingCertificate": sys.argv[3],
    }, output)
PY
  xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" \
    -exportPath "$STAGING_DIRECTORY/export" \
    -exportOptionsPlist "$STAGING_DIRECTORY/ExportOptions.plist"
  APP="$STAGING_DIRECTORY/export/Periodic.app"
fi

SPARKLE_TOOLS="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_TOOLS/generate_appcast" ]] ||
  fail "Sparkle release tools were not found at $SPARKLE_TOOLS."

if [[ "$MODE" != "--local" ]]; then
  ACTUAL_PUBLIC_KEY="$("$SPARKLE_TOOLS/generate_keys" --account "$KEY_ACCOUNT" -p)"
  [[ "$ACTUAL_PUBLIC_KEY" == "$PUBLIC_KEY" ]] ||
    fail "Keychain signing key does not match the public key embedded in the application."
fi

if [[ "$MODE" == "--publish" ]]; then
  LATEST_TAG="$(gh release list --repo occva/Periodic --limit 1 \
    --exclude-drafts --exclude-pre-releases --json tagName --jq '.[0].tagName // ""')"
  if [[ -n "$LATEST_TAG" ]]; then
    mkdir -p "$STAGING_DIRECTORY/previous"
    gh release download "$LATEST_TAG" --repo occva/Periodic \
      --pattern appcast.xml --dir "$STAGING_DIRECTORY/previous"
    "$SPARKLE_TOOLS/sign_update" --account "$KEY_ACCOUNT" --verify \
      "$STAGING_DIRECTORY/previous/appcast.xml"
    python3 "$PROJECT_ROOT/script/validate_release.py" \
      --next-build "$STAGING_DIRECTORY/previous/appcast.xml" "$BUILD_NUMBER"
  fi
fi

python3 "$PROJECT_ROOT/script/validate_release.py" "$APP" "$VERSION" "$BUILD_NUMBER" "$PUBLIC_KEY"
ARCHITECTURES="$(lipo "$APP/Contents/MacOS/Periodic" -archs)"
[[ "$ARCHITECTURES" == "arm64" ]] ||
  fail "Release app must contain only arm64 (Apple silicon); found $ARCHITECTURES."
codesign --verify --deep --strict "$APP"

notarize() {
  local artifact="$1"
  local result="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json > "$result"
  python3 - "$result" <<'PY'
import json
import sys
with open(sys.argv[1]) as source:
    result = json.load(source)
if result.get("status") != "Accepted":
    raise SystemExit("Notarization was not accepted; inspect " + sys.argv[1])
PY
}

if [[ "$IS_NOTARIZED" == true ]]; then
  ditto -c -k --keepParent "$APP" "$STAGING_DIRECTORY/Periodic.zip"
  notarize "$STAGING_DIRECTORY/Periodic.zip" "$OUTPUT_DIRECTORY/app-notarization.json"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute "$APP"
fi

"$PROJECT_ROOT/script/create_dmg.sh" "$APP" "$DMG" "Periodic"

if [[ "$IS_NOTARIZED" == true ]]; then
  codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
  notarize "$DMG" "$OUTPUT_DIRECTORY/dmg-notarization.json"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
if [[ "$MODE" != "--local" ]]; then
  UPDATE_ARCHIVES="$STAGING_DIRECTORY/updates"
  mkdir -p "$UPDATE_ARCHIVES"
  cp "$DMG" "$UPDATE_ARCHIVES/"
  cp "$PROJECT_ROOT/docs/releases/$VERSION.md" "$UPDATE_ARCHIVES/Periodic-$VERSION.md"
  "$SPARKLE_TOOLS/generate_appcast" --account "$KEY_ACCOUNT" \
    --download-url-prefix "https://github.com/occva/Periodic/releases/download/v$VERSION/" \
    --link "https://github.com/occva/Periodic/releases" \
    --embed-release-notes --maximum-deltas 0 \
    "$UPDATE_ARCHIVES"
  "$SPARKLE_TOOLS/sign_update" --account "$KEY_ACCOUNT" --verify "$UPDATE_ARCHIVES/appcast.xml"
  ARCHIVE_SIGNATURE="$(python3 - "$UPDATE_ARCHIVES/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
enclosure = ET.parse(sys.argv[1]).find("./channel/item/enclosure")
print(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"])
PY
)"
  "$SPARKLE_TOOLS/sign_update" --account "$KEY_ACCOUNT" --verify "$DMG" "$ARCHIVE_SIGNATURE"
  cp "$UPDATE_ARCHIVES/appcast.xml" "$OUTPUT_DIRECTORY/appcast.xml"
  python3 "$PROJECT_ROOT/script/validate_release.py" \
    "$APP" "$VERSION" "$BUILD_NUMBER" "$PUBLIC_KEY" "$OUTPUT_DIRECTORY/appcast.xml" "$DMG"
fi

(
  cd "$OUTPUT_DIRECTORY"
  shasum -a 256 "$(basename "$DMG")" > SHA256SUMS
)
if [[ "$MODE" == "--publish" ]]; then
  gh release create "v$VERSION" --repo occva/Periodic --target "$COMMIT" \
    --draft \
    --title "Periodic $VERSION" --notes-file "$PROJECT_ROOT/docs/releases/$VERSION.md" \
    "$DMG" "$OUTPUT_DIRECTORY/appcast.xml" "$OUTPUT_DIRECTORY/SHA256SUMS"
  gh release edit "v$VERSION" --repo occva/Periodic --draft=false --latest
fi

if [[ "$MODE" == "--local" ]]; then
  echo "Local validation package only (ad hoc signature, no notarization): $DMG"
elif [[ "$IS_NOTARIZED" == false ]]; then
  echo "Release package (ad hoc code signature, Sparkle signatures, no Apple notarization): $DMG"
else
  echo "Signed, notarized release package: $DMG"
fi
