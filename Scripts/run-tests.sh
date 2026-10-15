#!/usr/bin/env bash
# Runs StudioKitTests on an iPad simulator (Apple silicon) and writes build/test-report.json.
# Optional: Scripts/fetch-test-raws.sh first, to include the RAW decoding tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
export TEST_RUNNER_STUDIO_RAW_DIR="${STUDIO_RAW_DIR:-$ROOT/build/test-raws}"
export TEST_RUNNER_STUDIO_TEST_REPORT="$ROOT/build/test-report.json"
cd "$ROOT/Packages/StudioKit"
xcodebuild -scheme StudioKit -destination "$DEST" -derivedDataPath "$ROOT/build/dd" ARCHS=arm64 test 2>&1 | tee "$ROOT/build/test.log" | grep -E "Test Case|error:|Executed|TEST (SUCCEEDED|FAILED)|skipped"
