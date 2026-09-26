#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-unit}"
SOURCE_RESULT="${2:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIRECTORY="$PROJECT_ROOT/build/TestResults"

if [[ "$MODE" == "--performance" ]]; then
  exec "$PROJECT_ROOT/script/performance.sh" "${@:2}"
fi

latest_result() {
  local latest=""
  local candidate
  for candidate in "$RESULT_DIRECTORY"/*.xcresult; do
    [[ -e "$candidate" ]] || continue
    if [[ -z "$latest" || "$candidate" -nt "$latest" ]]; then
      latest="$candidate"
    fi
  done
  printf '%s\n' "$latest"
}

TEST_FILTER=()
case "$MODE" in
  unit)
    TEST_FILTER=(
      -only-testing:PeriodicTests
      -skip-testing:PeriodicTests/SubscriptionPerformanceTests
    )
    ;;
  --ui)
    TEST_FILTER=(-only-testing:PeriodicUITests)
    ;;
  --all)
    TEST_FILTER=(-skip-testing:PeriodicTests/SubscriptionPerformanceTests)
    ;;
  --failed)
    if [[ -z "$SOURCE_RESULT" ]]; then
      SOURCE_RESULT="$(latest_result)"
    fi
    if [[ -z "$SOURCE_RESULT" || ! -d "$SOURCE_RESULT" ]]; then
      echo "找不到用于提取失败测试的 .xcresult。" >&2
      exit 2
    fi

    SUMMARY_JSON="$(
      xcrun xcresulttool get test-results summary --path "$SOURCE_RESULT"
    )"
    while IFS= read -r test_identifier; do
      [[ -n "$test_identifier" ]] || continue
      TEST_FILTER+=("-only-testing:$test_identifier")
    done < <(
      jq -r '
        (.testFailures // [])
        | map(.targetName + "/" + (.testIdentifierString | sub("\\(\\)$"; "")))
        | unique[]
      ' <<< "$SUMMARY_JSON"
    )

    if [[ ${#TEST_FILTER[@]} -eq 0 ]]; then
      echo "结果中没有失败测试，无需重跑：$SOURCE_RESULT"
      exit 0
    fi

    echo "仅重跑以下失败测试："
    printf '  %s\n' "${TEST_FILTER[@]#-only-testing:}"
    ;;
  *)
    echo "usage: $0 [unit|--ui|--all|--failed [result.xcresult]|--performance]" >&2
    exit 2
    ;;
esac

mkdir -p "$RESULT_DIRECTORY"
RESULT_PATH="$RESULT_DIRECTORY/$(date +%Y%m%d-%H%M%S)-$$.xcresult"
cd "$PROJECT_ROOT"

set +e
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
TEST_STATUS=$?
set -e

echo "Test results: $RESULT_PATH"
if [[ $TEST_STATUS -ne 0 ]]; then
  echo "Retry failures only: $0 --failed \"$RESULT_PATH\""
fi
exit "$TEST_STATUS"
