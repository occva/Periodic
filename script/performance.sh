#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if [[ "$MODE" != "run" && "$MODE" != "--record-baseline" ]]; then
  echo "usage: $0 [--record-baseline]" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIRECTORY="$PROJECT_ROOT/build/PerformanceResults"
BASELINE_PATH="$PROJECT_ROOT/script/baselines/subscription-analytics.json"
RESULT_PATH="$RESULT_DIRECTORY/$(date +%Y%m%d-%H%M%S)-$$.xcresult"
METRICS_PATH="${RESULT_PATH%.xcresult}-metrics.json"
ARCHITECTURE="$(uname -m)"
OS_VERSION="$(sw_vers -productVersion)"
XCODE_BUILD="$(xcodebuild -version | awk '/Build version/ { print $3 }')"

mkdir -p "$RESULT_DIRECTORY"

set +e
xcodebuild -quiet \
  -project "$PROJECT_ROOT/Periodic.xcodeproj" \
  -scheme Periodic \
  -configuration Release \
  -destination "platform=macOS,arch=$ARCHITECTURE" \
  -derivedDataPath "$PROJECT_ROOT/build/DerivedData-Performance" \
  -resultBundlePath "$RESULT_PATH" \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -only-testing:PeriodicTests/SubscriptionPerformanceTests/testThousandSubscriptionAnalyticsPerformance \
  ENABLE_TESTABILITY=YES \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=TEST_SUPPORT \
  ENABLE_HARDENED_RUNTIME=NO \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  test
TEST_STATUS=$?
set -e

echo "Performance results: $RESULT_PATH"
if [[ $TEST_STATUS -ne 0 ]]; then
  exit "$TEST_STATUS"
fi

xcrun xcresulttool get test-results metrics --path "$RESULT_PATH" > "$METRICS_PATH"

metric_average() {
  local identifier="$1"
  jq -er --arg identifier "$identifier" '
    [
      .[]
      | .testRuns[]
      | .metrics[]
      | select(.identifier == $identifier)
      | .measurements[]
    ]
    | if length == 0 then error("missing metric: " + $identifier) else add / length end
  ' "$METRICS_PATH"
}

CLOCK_AVERAGE="$(metric_average com.apple.dt.XCTMetric_Clock.time.monotonic)"
INSTRUCTION_AVERAGE="$(metric_average com.apple.dt.XCTMetric_CPU.instructions_retired)"

record_baseline() {
  local baseline_directory
  local temporary_path
  baseline_directory="$(dirname "$BASELINE_PATH")"
  mkdir -p "$baseline_directory"
  temporary_path="$(mktemp "$baseline_directory/.subscription-analytics.XXXXXX")"
  jq -n \
    --arg architecture "$ARCHITECTURE" \
    --arg operatingSystem "$OS_VERSION" \
    --arg xcodeBuild "$XCODE_BUILD" \
    --argjson clockAverage "$CLOCK_AVERAGE" \
    --argjson instructionAverage "$INSTRUCTION_AVERAGE" \
    '{
      schemaVersion: 1,
      testIdentifier: "SubscriptionPerformanceTests/testThousandSubscriptionAnalyticsPerformance()",
      configuration: "Release",
      environment: {
        architecture: $architecture,
        operatingSystem: $operatingSystem,
        xcodeBuild: $xcodeBuild
      },
      metrics: {
        clockMonotonicSeconds: {
          average: $clockAverage,
          maximumRegressionPercent: 25
        },
        cpuInstructionsRetiredKiloInstructions: {
          average: $instructionAverage,
          maximumRegressionPercent: 15
        }
      }
    }' > "$temporary_path"
  mv "$temporary_path" "$BASELINE_PATH"
  echo "Recorded performance baseline: $BASELINE_PATH"
}

if [[ "$MODE" == "--record-baseline" ]]; then
  record_baseline
  exit 0
fi

if [[ ! -f "$BASELINE_PATH" ]]; then
  echo "缺少性能基线。确认结果后运行 $0 --record-baseline。" >&2
  exit 2
fi

BASELINE_ARCHITECTURE="$(jq -er '.environment.architecture' "$BASELINE_PATH")"
BASELINE_OS_VERSION="$(jq -er '.environment.operatingSystem' "$BASELINE_PATH")"
BASELINE_XCODE_BUILD="$(jq -er '.environment.xcodeBuild' "$BASELINE_PATH")"
if [[ "$ARCHITECTURE" != "$BASELINE_ARCHITECTURE" \
  || "$OS_VERSION" != "$BASELINE_OS_VERSION" \
  || "$XCODE_BUILD" != "$BASELINE_XCODE_BUILD" ]]; then
  echo "当前环境与性能基线不一致，不能直接比较。" >&2
  echo "Current:  $ARCHITECTURE / macOS $OS_VERSION / Xcode $XCODE_BUILD" >&2
  echo "Baseline: $BASELINE_ARCHITECTURE / macOS $BASELINE_OS_VERSION / Xcode $BASELINE_XCODE_BUILD" >&2
  echo "确认新环境结果后运行 $0 --record-baseline。" >&2
  exit 2
fi

check_metric() {
  local label="$1"
  local current="$2"
  local baseline_key="$3"
  local baseline
  local regression_percent
  local limit

  baseline="$(jq -er ".metrics.$baseline_key.average" "$BASELINE_PATH")"
  regression_percent="$(
    jq -er ".metrics.$baseline_key.maximumRegressionPercent" "$BASELINE_PATH"
  )"
  limit="$(
    awk -v baseline="$baseline" -v percent="$regression_percent" \
      'BEGIN { printf "%.12f", baseline * (1 + percent / 100) }'
  )"

  printf '%s: current %.6f, baseline %.6f, limit %.6f\n' \
    "$label" "$current" "$baseline" "$limit"
  awk -v current="$current" -v limit="$limit" 'BEGIN { exit !(current <= limit) }'
}

FAILED=0
if ! check_metric \
  "Clock seconds" \
  "$CLOCK_AVERAGE" \
  clockMonotonicSeconds; then
  FAILED=1
fi
if ! check_metric \
  "CPU retired kI" \
  "$INSTRUCTION_AVERAGE" \
  cpuInstructionsRetiredKiloInstructions; then
  FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then
  echo "Performance regression exceeded the recorded tolerance." >&2
  exit 1
fi

echo "Performance baseline check passed."
