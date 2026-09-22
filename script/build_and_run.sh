#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--sample-data) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--sample-data]" >&2; exit 2 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Periodic"
BUNDLE_ID="local.lhg.Periodic"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cd "$PROJECT_ROOT"

# Stop the app before replacing its executable. Never kill by a partial name.
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild -quiet \
  -project "$PROJECT_ROOT/Periodic.xcodeproj" \
  -scheme Periodic \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug)
    xcrun lldb -- "$APP_BINARY"
    ;;
  --logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify)
    open_app
    for attempt in {1..10}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        echo "Build and launch verified: $APP_BUNDLE"
        exit 0
      fi
      sleep 0.5
    done
    echo "Build succeeded, but $APP_NAME did not stay running." >&2
    exit 1
    ;;
  --sample-data)
    /usr/bin/open -n "$APP_BUNDLE" --args -store-in-memory -seed-test-data
    ;;
esac
