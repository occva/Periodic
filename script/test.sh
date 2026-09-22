#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-unit}"
TEST_FILTER=()
case "$MODE" in
  unit) TEST_FILTER=(-only-testing:PeriodicTests) ;;
  --ui) TEST_FILTER=(-only-testing:PeriodicUITests) ;;
  --all) ;;
  *) echo "usage: $0 [unit|--ui|--all]" >&2; exit 2 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_PATH="$PROJECT_ROOT/build/TestResults/$(date +%Y%m%d-%H%M%S)-$$.xcresult"
mkdir -p "$PROJECT_ROOT/build/TestResults"
cd "$PROJECT_ROOT"

xcodebuild -quiet \
  -project "$PROJECT_ROOT/Periodic.xcodeproj" \
  -scheme Periodic \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$PROJECT_ROOT/build/DerivedData" \
  -resultBundlePath "$RESULT_PATH" \
  -parallel-testing-enabled NO \
  ${TEST_FILTER[@]+"${TEST_FILTER[@]}"} \
  test

echo "Test results: $RESULT_PATH"
