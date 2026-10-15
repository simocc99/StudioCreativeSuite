#!/usr/bin/env bash
# Runs the test suite on a connected iPad, hosted by the app (needs App/Config/Local.xcconfig).
#   Scripts/run-device-tests.sh <device UDID>
# RAW samples in build/test-raws are copied into the app's Documents/TestRAW first (test data only),
# and the expected/observed report is copied back to build/device-test-report.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:?UDID del dispositivo (xcrun devicectl list devices)}"
BID="$(xcodebuild -project "$ROOT/App/StudioCreativeSuite.xcodeproj" -scheme StudioCreativeSuite -showBuildSettings 2>/dev/null | awk '/ PRODUCT_BUNDLE_IDENTIFIER =/{print $3; exit}')"
DD="$ROOT/build/dd-devtest"
cd "$ROOT"
xcodebuild -workspace StudioCreativeSuite.xcworkspace -scheme StudioCreativeSuite -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$DD" -allowProvisioningUpdates build-for-testing
# install the host app so its data container exists, then stage the samples
xcrun devicectl device install app --device "$UDID" "$DD/Build/Products/Debug-iphoneos/StudioCreativeSuite.app" >/dev/null
if ls "$ROOT"/build/test-raws/* >/dev/null 2>&1; then
  for f in "$ROOT"/build/test-raws/*; do
    xcrun devicectl device copy to --device "$UDID" --domain-type appDataContainer --domain-identifier "$BID" \
      --source "$f" --destination "Documents/TestRAW/$(basename "$f")" >/dev/null
  done
fi
xcodebuild -workspace StudioCreativeSuite.xcworkspace -scheme StudioCreativeSuite -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$DD" -allowProvisioningUpdates test-without-building 2>&1 | tee "$ROOT/build/device-test.log" \
  | grep -E "Test Case|error:|Executed|TEST (SUCCEEDED|FAILED)|EXECUTE"
