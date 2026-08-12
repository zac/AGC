#!/bin/sh
# Build a headless yaAGC tracer against references/yaAGC (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YAAGC="${YAAGC_ROOT:-$ROOT/references/yaAGC}"
OUT="${OUT:-$ROOT/Tools/yaagc-trace/yaagc-trace}"

if [ ! -f "$YAAGC/agc_engine.c" ]; then
  echo "yaAGC not found at $YAAGC" >&2
  echo "Clone Virtual AGC's yaAGC sources into references/yaAGC, or set YAAGC_ROOT." >&2
  exit 1
fi

cc -O2 -std=gnu99 -o "$OUT" \
  -I"$YAAGC" -I"$ROOT/Tools/yaagc-trace" \
  -Wno-deprecated-non-prototype -Wno-unused-parameter -Wno-unused-variable \
  "$ROOT/Tools/yaagc-trace/main.c" \
  "$ROOT/Tools/yaagc-trace/stubs.c" \
  "$YAAGC/agc_engine.c" \
  "$YAAGC/agc_engine_init.c" \
  "$YAAGC/rfopen.c"

echo "built $OUT"
