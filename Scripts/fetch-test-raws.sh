#!/usr/bin/env bash
# Downloads one CC0 raw sample per format from raw.pixls.us into build/test-raws (not committed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/build/test-raws"
mkdir -p "$D"
for p in "Canon/Canon%20EOS%20R10" "Canon/EOS%205D%20Mark%20III" "Nikon/D750" "Sony/ILCE-7M3" "Fujifilm/X-E3" \
         "Panasonic/DC-G9" "Apple/iPhone%2012%20Pro" "Leica/M10" "Google/Pixel%204a"; do
  f=$(curl -sL "https://raw.pixls.us/data/$p/" | grep -oE 'href="[^"?/]+\.(dng|DNG|CR2|CR3|NEF|ARW|RAF|RW2)"' | head -1 | sed 's/href="//;s/"$//')
  [ -n "$f" ] || { echo "skip $p"; continue; }
  out="$D/$(echo "$p" | tr '/%' '__')_$f"
  [ -f "$out" ] || curl -sL --fail -o "$out" "https://raw.pixls.us/data/$p/$f"
  echo "$out"
done
