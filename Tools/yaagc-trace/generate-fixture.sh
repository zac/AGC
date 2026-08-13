#!/bin/sh
# Rebuild the tracer and refresh Tests/AGCTests/Fixtures golden traces.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/Tools/yaagc-trace/build.sh"
mkdir -p "$ROOT/Tests/AGCTests/Fixtures"
ROM="$ROOT/Tests/AGCTests/Luminary099.bin"
TRACE="$ROOT/Tools/yaagc-trace/yaagc-trace"

"$TRACE" "$ROM" 1000000 \
  > "$ROOT/Tests/AGCTests/Fixtures/luminary099-boot.jsonl"
echo "wrote luminary099-boot.jsonl"

# V35E: VERB 3 5 ENTR after 1e6 boot, 50000 MCT/key.
"$TRACE" "$ROM" 1200000 --keys 1000001:21,1050001:3,1100001:5,1150001:34 \
  > "$ROOT/Tests/AGCTests/Fixtures/luminary099-v35e.jsonl"
echo "wrote luminary099-v35e.jsonl"

# V37E63E: VERB 3 7 ENTR 6 3 ENTR.
"$TRACE" "$ROM" 1350000 --keys 1000001:21,1050001:3,1100001:7,1150001:34,1200001:6,1250001:3,1300001:34 \
  > "$ROOT/Tests/AGCTests/Fixtures/luminary099-v37e63e.jsonl"
echo "wrote luminary099-v37e63e.jsonl"
