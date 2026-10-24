#!/usr/bin/env bash
# Build or test the Queue scheme for the iOS Simulator.
# Usage: xcodebuild-simulator.sh <build|test> <destination> [extra xcodebuild args...]
# QUEUE_RESULT_BUNDLE overrides the xcresult file name (default QueueTests.xcresult).
set -euo pipefail

action="${1:?usage: xcodebuild-simulator.sh build|test <destination> [extra xcodebuild args...]}"
destination="${2:?destination required}"
shift 2

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

entitlements="$root/.github/ci/Empty.entitlements"
log_dir="${RUNNER_TEMP:-/tmp}"
mkdir -p "$log_dir"

args=(
  -project "$root/Queue.xcodeproj"
  -scheme Queue
  -configuration Debug
  -sdk iphonesimulator
  -destination "$destination"
  -destination-timeout 180
  -derivedDataPath "$root/DerivedData"
  -skipPackagePluginValidation
  -skipMacroValidation
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=YES
  "DEVELOPMENT_TEAM="
  "PROVISIONING_PROFILE_SPECIFIER="
  "CODE_SIGN_ENTITLEMENTS=$entitlements"
  ENABLE_TESTABILITY=YES
  COMPILER_INDEX_STORE_ENABLE=NO
)

case "$action" in
  build)
    xcodebuild build "${args[@]}" -showBuildTimingSummary \
      2>&1 | tee "$log_dir/xcodebuild-build.log"
    ;;
  test)
    result_name="${QUEUE_RESULT_BUNDLE:-QueueTests.xcresult}"
    rm -rf "$log_dir/$result_name"
    xcodebuild test "${args[@]}" \
      "$@" \
      -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -resultBundlePath "$log_dir/$result_name" \
      2>&1 | tee "$log_dir/xcodebuild-test.log"
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac
