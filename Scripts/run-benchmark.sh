#!/usr/bin/env bash
# Runs the in-app benchmark on a connected iPad and copies Documents/benchmark.json back.
#   Scripts/run-benchmark.sh <UDID>    (RAW samples: Scripts/run-device-tests.sh stages them in Documents/TestRAW)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
U="${1:?UDID}"
B="$(xcodebuild -project "$ROOT/App/StudioCreativeSuite.xcodeproj" -scheme StudioCreativeSuite -showBuildSettings 2>/dev/null | awk '/ PRODUCT_BUNDLE_IDENTIFIER =/{print $3; exit}')"
OUT="$ROOT/build/benchmark-device.json"
rm -f "$OUT"
xcrun devicectl device process launch --device "$U" --terminate-existing "$B" -- -StudioBenchmark YES
for i in $(seq 1 90); do
  sleep 10
  if xcrun devicectl device copy from --device "$U" --domain-type appDataContainer --domain-identifier "$B" \
       --source Documents/benchmark.json --destination "$OUT" >/dev/null 2>&1; then
    # the file appears at the end of the run; it must be newer than the launch
    python3 -c "import json,sys,datetime;d=json.load(open('$OUT'));t=datetime.datetime.fromisoformat(d['date'].replace('Z','+00:00'));sys.exit(0 if (datetime.datetime.now(datetime.timezone.utc)-t).total_seconds()<900 else 1)" && break
  fi
done
python3 - "$OUT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d['device'],d['system'],round(d['physicalMemoryGB'],1),'GB')
for r in d['results']:
    print(f"{r['name'][:52]:52} {r['ms']:9.1f} ms  picco {r['peakMB']:6.0f} MB  {'OK' if r['ok'] else 'ERR'}  {r['note'][:60]}")
PY
