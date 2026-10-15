#!/usr/bin/env bash
# CI build: Release archive without a certificate, packaged as an .ipa that SideStore,
# AltStore or LiveContainer re-sign on the device. Writes into build/ci/:
#   StudioCreativeSuite.ipa   the package
#   build-info.json           metadata for the AltSource (version, size, sha256, permissions)
#
# The app is ad-hoc signed ("fake-signed", no identity) with App/Config/StudioApp.entitlements
# so the sideloading tool can read which entitlements the app asks for. No secrets involved.
#
# Environment (all optional):
#   STUDIO_BUNDLE_ID     bundle identifier (default com.example.studiocreativesuite)
#   STUDIO_BUILD_NUMBER  CFBundleVersion (default 1)
#   STUDIO_REPOSITORY    owner/repo, used for the download URL in build-info.json
#   STUDIO_RELEASE_TAG   release that will hold the .ipa (default build-$STUDIO_BUILD_NUMBER)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_NAME=StudioCreativeSuite
OUT="$ROOT/build/ci"
DD="$ROOT/build/dd-ci"
BID="${STUDIO_BUNDLE_ID:-com.example.studiocreativesuite}"
BUILD="${STUDIO_BUILD_NUMBER:-1}"
TAG="${STUDIO_RELEASE_TAG:-build-$BUILD}"

[ -d "$ROOT/Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework" ] || "$ROOT/Scripts/build-photo-engine.sh"

rm -rf "$OUT"
mkdir -p "$OUT"
ARCHIVE="$OUT/$APP_NAME.xcarchive"

xcodebuild -project "$ROOT/App/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DD" -archivePath "$ARCHIVE" \
  STUDIO_BUNDLE_ID="$BID" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive

STAGE="$OUT/stage"
mkdir -p "$STAGE/Payload"
cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$STAGE/Payload/"
APP="$STAGE/Payload/$APP_NAME.app"

# ad-hoc signature carrying the entitlements, inside out
find "$APP" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) -print0 |
  while IFS= read -r -d '' f; do codesign -f -s - "$f"; done
codesign -f -s - --entitlements "$ROOT/App/Config/StudioApp.entitlements" --generate-entitlement-der "$APP"

(cd "$STAGE" && /usr/bin/zip -qry "$OUT/$APP_NAME.ipa" Payload)
"$ROOT/Scripts/verify-ipa.sh" "$OUT/$APP_NAME.ipa" "$BID"

python3 -I "$ROOT/Scripts/ci/build_info.py" --app "$APP" --ipa "$OUT/$APP_NAME.ipa" \
  --repo "${STUDIO_REPOSITORY:-}" --tag "$TAG" --output "$OUT/build-info.json"
xcodebuild -version > "$OUT/xcode-version.txt"
rm -rf "$STAGE"
echo "==> $OUT"
