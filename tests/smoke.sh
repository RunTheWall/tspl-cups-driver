#!/bin/sh
# ============================================================================
#  Hardware-free smoke test for rastertotspl: feed it a known synthetic CUPS
#  raster (tests/mkras.c) and assert the exact TSPL that comes out.
#  Run from anywhere:  sh tests/smoke.sh    (CI runs it on amd64 + arm64)
# ============================================================================
set -eu
cd "$(dirname "$0")/.."
LC_ALL=C; export LC_ALL   # the TSPL output is binary; keep tr/grep byte-safe

fail() { echo "FAIL: $*" 1>&2; exit 1; }

[ -f src/rastertotspl ] || make -s
CUPSCFG="$(cups-config --cflags 2>/dev/null || true)"
CUPSLIBS="$(cups-config --libs 2>/dev/null || echo -lcups)"
# shellcheck disable=SC2086
cc -O2 $CUPSCFG -o tests/mkras tests/mkras.c $CUPSLIBS

OUT="${TMPDIR:-/tmp}/tspl-smoke.$$"
trap 'rm -f "$OUT" "$OUT.ras" "$OUT.txt" "$OUT.hex"' EXIT

tests/mkras > "$OUT.ras"
src/rastertotspl 1 tester smoke 3 '' < "$OUT.ras" > "$OUT" 2>/dev/null

tr -d '\r' < "$OUT" > "$OUT.txt"
od -An -v -tx1 < "$OUT" | tr -d ' \n' > "$OUT.hex"

# --- the TSPL header, line by line (12x8 px @300dpi -> 1x1 mm; note the
#     spec-required space before "mm") ---
for cmd in 'SIZE 1 mm,1 mm' 'GAP 3 mm,0 mm' 'DENSITY 8' 'SPEED 4' \
           'DIRECTION 0,0' 'REFERENCE 0,0' 'CLS'; do
    grep -q "^$cmd" "$OUT.txt" || fail "missing TSPL command: $cmd"
done

# --- both pages present ---
[ "$(grep -c '^SIZE' "$OUT.txt")" = 2 ] || fail "expected 2 pages"

# --- bitmap: 2 bytes/row x 8 rows, mode 1 (OR — the field-proven consensus).
#     Row 0: 12 black px (TSPL: 0-bit = dot) -> 00, then 0f: the 4 pad bits
#     beyond the page width MUST stay 1/white (0-padding prints black stripes
#     down the right edge). Rows 1-7 white -> ff. ---
BITMAP_HDR=4249544d415020302c302c322c382c312c
grep -q "${BITMAP_HDR}000fffffffffffffffffffffffffff" "$OUT.hex" \
    || fail "page-1 bitmap bytes wrong (header/mode/polarity/packing/padding?)"

# --- copies: driven by the raster header's NumCopies (page 1 -> 1, page 2
#     -> 4), never by argv[4] (which is 3 here and must have no effect) ---
grep -q '^PRINT 1,1$' "$OUT.txt" || fail "page 1 should print 1 copy"
grep -q '^PRINT 1,4$' "$OUT.txt" || fail "page 2 should print 4 device copies"
grep -q '^PRINT 1,3$' "$OUT.txt" && fail "argv[4] copies leaked into PRINT"

# --- option handling: BlackMark -> BLINE (no GAP), PrintSpeed=0 -> no SPEED ---
src/rastertotspl 1 tester smoke 1 'MediaTracking=BlackMark PrintSpeed=0' \
    < "$OUT.ras" 2>/dev/null | tr -d '\r' > "$OUT.txt"
grep -q  '^BLINE 3 mm,0 mm' "$OUT.txt" || fail "BlackMark should emit BLINE"
grep -q  '^GAP'   "$OUT.txt" && fail "BlackMark must not also emit GAP"
grep -q  '^SPEED' "$OUT.txt" && fail "PrintSpeed=0 must omit SPEED"

# --- continuous media -> GAP 0 ---
src/rastertotspl 1 tester smoke 1 'MediaTracking=Continuous' \
    < "$OUT.ras" 2>/dev/null | tr -d '\r' > "$OUT.txt"
grep -q '^GAP 0 mm,0 mm' "$OUT.txt" || fail "Continuous should emit GAP 0"

echo "smoke test OK"
