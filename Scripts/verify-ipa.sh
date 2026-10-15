#!/usr/bin/env bash
# Structural checks on an .ipa: Payload layout, arm64 iPhoneOS executable, asset catalog,
# photo engine linked. Used by build-ipa.sh and by CI.
#
#   Scripts/verify-ipa.sh path/to/StudioCreativeSuite.ipa [expected-bundle-id]
set -euo pipefail

IPA="$1"
EXPECTED_BID="${2:-}"
APP_NAME=StudioCreativeSuite

echo "==> verifying $IPA"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
unzip -q "$IPA" -d "$CHECK"
APPDIR="$CHECK/Payload/$APP_NAME.app"
fail() { echo "FAIL: $*"; exit 1; }
[ -d "$APPDIR" ] || fail "Payload/$APP_NAME.app missing"
[ -f "$APPDIR/Info.plist" ] || fail "Info.plist missing"
BIN="$APPDIR/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPDIR/Info.plist")"
[ -f "$BIN" ] || fail "executable missing"
ARCH="$(lipo -archs "$BIN")"
[ "$ARCH" = "arm64" ] || fail "unexpected architectures: $ARCH"
MINOS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APPDIR/Info.plist")"
FAMILY="$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$APPDIR/Info.plist")"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPDIR/Info.plist")"
PLATFORM="$(/usr/libexec/PlistBuddy -c 'Print :DTPlatformName' "$APPDIR/Info.plist")"
[ "$PLATFORM" = "iphoneos" ] || fail "platform $PLATFORM"
[ -f "$APPDIR/Assets.car" ] || fail "asset catalog missing"
# exported symbol in plain builds; archives strip symbols but keep the engine's version string
nm -gU "$BIN" 2>/dev/null | grep -q _sc_photo_open || LC_ALL=C grep -aq "studio-photo-engine [0-9.]* / lightcraft" "$BIN" \
  || fail "photo engine not linked"
[ -z "$EXPECTED_BID" ] || [ "$BID" = "$EXPECTED_BID" ] || fail "bundle id $BID, expected $EXPECTED_BID"
echo "OK: arm64, MinimumOSVersion $MINOS, UIDeviceFamily $FAMILY (2 = iPad), bundle id $BID"
du -h "$IPA"
