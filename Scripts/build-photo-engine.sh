#!/usr/bin/env bash
# Builds the Rust photo engine (LightCraft bridge) as a static XCFramework for
# iPadOS devices (aarch64-apple-ios) and the Apple-silicon simulator (aarch64-apple-ios-sim).
# Output: Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework
#
# Requirements: Xcode command line tools and rustup with both targets:
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/Engines/studio-photo-engine"
OUT="$ROOT/Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework"
TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim)

if ! command -v cargo >/dev/null; then
  for p in "$HOME/.cargo/bin" /opt/homebrew/opt/rustup/bin; do [ -x "$p/cargo" ] && export PATH="$p:$PATH"; done
fi
command -v cargo >/dev/null || { echo "error: cargo not found (install rustup)"; exit 1; }

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-18.0}"

for t in "${TARGETS[@]}"; do
  rustup target list --installed | grep -qx "$t" || rustup target add "$t"
  echo "==> cargo build --release --target $t"
  (cd "$CRATE" && cargo build --release --lib --target "$t")
done

HDR="$(mktemp -d)"
cp "$CRATE/include/StudioPhotoEngine.h" "$CRATE/include/module.modulemap" "$HDR/"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework \
  -library "$CRATE/target/aarch64-apple-ios/release/libstudio_photo_engine.a" -headers "$HDR" \
  -library "$CRATE/target/aarch64-apple-ios-sim/release/libstudio_photo_engine.a" -headers "$HDR" \
  -output "$OUT"
rm -rf "$HDR"
echo "==> $OUT"
du -sh "$OUT"
