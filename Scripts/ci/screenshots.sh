#!/usr/bin/env bash
# Builds the app for the simulator, boots an iPad Pro 13" (falls back to any iPad) and
# captures each demo scene (App/StudioApp/DemoScenes.swift) into build/screenshots/<scene>.png.
# Meant for CI; locally it works too but keeps a simulator busy for a few minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/screenshots"
DD="$ROOT/build/dd-shots"
SCENES=(home list photo raster vector paint video motion animation audio layout)
WAIT="${SCENE_WAIT:-10}"

[ -d "$ROOT/Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework" ] || "$ROOT/Scripts/build-photo-engine.sh"

xcodebuild -project "$ROOT/App/StudioCreativeSuite.xcodeproj" -scheme StudioCreativeSuite -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$DD/Build/Products/Debug-iphonesimulator/StudioCreativeSuite.app"
[ -d "$APP" ] || { echo "simulator build failed"; exit 1; }
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in d if "iOS" in r), reverse=True)
pads = [(r, x) for r in runtimes for x in d[r] if "iPad" in x["name"]]
best = next((x for r, x in pads if x["name"].startswith("iPad Pro 13")), pads[0][1] if pads else None)
print(best["udid"] if best else "")')
[ -n "$UDID" ] || { echo "no iPad simulator available"; exit 1; }
echo "==> simulator $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 || true
# Screenshots stay portrait: the app cannot force orientation on iPadOS 26+ and CI cannot
# drive the Simulator app's Rotate menu.
xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

rm -rf "$OUT"
mkdir -p "$OUT"
for s in "${SCENES[@]}"; do
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  sleep 1
  if ! xcrun simctl launch "$UDID" "$BID" -StudioScene "$s" >/dev/null; then
    echo "::warning::launch of $s failed; retrying"
    sleep 5
    xcrun simctl launch "$UDID" "$BID" -StudioScene "$s" >/dev/null || { echo "::warning::skipping $s"; continue; }
  fi
  case "$s" in video|audio|photo) sleep $((WAIT * 2)) ;; *) sleep "$WAIT" ;; esac
  xcrun simctl io "$UDID" screenshot "$OUT/$s.png" >/dev/null
  echo "captured $s"
done
xcrun simctl terminate "$UDID" "$BID" || true
ls -la "$OUT"
