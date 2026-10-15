#!/usr/bin/env bash
# Produces build/ipa/StudioCreativeSuite.ipa for sideloading (SideStore / AltStore re-sign it
# on the device with your own Apple Account) and checks the package structure.
#
#   Scripts/build-ipa.sh            unsigned Release build packaged as .ipa (for SideStore)
#   Scripts/build-ipa.sh --signed   archive + export signed with your team (development)
#
# Nothing here asks for or stores credentials: signing (if any) uses the team configured in
# App/Config/Local.xcconfig and the certificates Xcode already manages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/ipa"
DD="$ROOT/build/dd-ipa"
APP_NAME=StudioCreativeSuite
SIGNED=0
[ "${1:-}" = "--signed" ] && SIGNED=1

[ -d "$ROOT/Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework" ] || "$ROOT/Scripts/build-photo-engine.sh"

rm -rf "$OUT"
mkdir -p "$OUT"

if [ "$SIGNED" = 1 ]; then
  ARCHIVE="$OUT/$APP_NAME.xcarchive"
  xcodebuild -project "$ROOT/App/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" -archivePath "$ARCHIVE" -allowProvisioningUpdates archive
  cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>debugging</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
EOF
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
  IPA="$OUT/$APP_NAME.ipa"
else
  xcodebuild -project "$ROOT/App/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
  APP="$DD/Build/Products/Release-iphoneos/$APP_NAME.app"
  STAGE="$(mktemp -d)"
  mkdir -p "$STAGE/Payload"
  cp -R "$APP" "$STAGE/Payload/"
  (cd "$STAGE" && /usr/bin/zip -qry "$OUT/$APP_NAME.ipa" Payload)
  rm -rf "$STAGE"
  IPA="$OUT/$APP_NAME.ipa"
fi

"$ROOT/Scripts/verify-ipa.sh" "$IPA"
