#!/bin/sh
# ============================================================================
#  Hardware-free smoke test for rastertotspl: feed it a known synthetic CUPS
#  raster (tests/mkras.c) and assert the exact TSPL that comes out.
#  Run from anywhere:  sh tests/smoke.sh    (CI runs it on amd64 + arm64)
#  SPDX-License-Identifier: MIT
# ============================================================================
set -eu
cd "$(dirname "$0")/.."
LC_ALL=C; export LC_ALL   # the TSPL output is binary; keep tr/grep byte-safe

fail() { echo "FAIL: $*" 1>&2; exit 1; }

# One build definition for everything (the Makefile knows the CUPS libs);
# always invoke make so an edited filter can't be tested stale.
make -s src/rastertotspl tests/mkras

OUT="${TMPDIR:-/tmp}/tspl-smoke.$$"
trap 'rm -f "$OUT" "$OUT.ras" "$OUT.txt" "$OUT.hex" "$OUT.err"' EXIT

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
#     down the right edge). Rows 1-7 white -> 14 x ff, built with printf so
#     the byte count can't silently drift. ---
BITMAP_HDR=4249544d415020302c302c322c382c312c
WHITE=$(printf 'ff%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14)
grep -q "${BITMAP_HDR}000f${WHITE}" "$OUT.hex" \
    || fail "page-1 bitmap bytes wrong (header/mode/polarity/packing/padding?)"

# --- copies: driven by the raster header's NumCopies (page 1 -> 1, page 2
#     -> 4), never by argv[4] (which is 3 here and must have no effect) ---
grep -q '^PRINT 1,1$' "$OUT.txt" || fail "page 1 should print 1 copy"
grep -q '^PRINT 1,4$' "$OUT.txt" || fail "page 2 should print 4 device copies"
grep -q '^PRINT 1,3$' "$OUT.txt" && fail "argv[4] copies leaked into PRINT"

# --- option handling: BlackMark -> BLINE (no GAP), PrintSpeed=0 -> no SPEED ---
opt() { src/rastertotspl 1 tester smoke 1 "$1" < "$OUT.ras" 2>"$OUT.err" | tr -d '\r' > "$OUT.txt"; }
opt 'MediaTracking=BlackMark PrintSpeed=0'
grep -qx 'BLINE 3 mm,0 mm' "$OUT.txt" || fail "BlackMark should emit BLINE 3 mm"
grep -q  '^GAP'   "$OUT.txt" && fail "BlackMark must not also emit GAP"
grep -q  '^SPEED' "$OUT.txt" && fail "PrintSpeed=0 must omit SPEED"

# --- continuous roll -> GAP 0 and SIZE stays the page height (nothing to add:
#     the page IS the feed length); out-of-range speed clamps to 6 ips ---
opt 'MediaTracking=Continuous PrintSpeed=9'
grep -qx 'GAP 0 mm,0 mm'  "$OUT.txt" || fail "Continuous should emit GAP 0"
grep -qx 'SIZE 1 mm,1 mm' "$OUT.txt" || fail "Continuous must not pad SIZE"
grep -qx 'SPEED 6'        "$OUT.txt" || fail "PrintSpeed=9 should clamp to SPEED 6"

# --- GapLength (tenths of mm) on the sensor modes: whole millimetres keep the
#     integer form, fractions are spec ("GAP 7.62 mm,2.54 mm" is a manual
#     example); a bare 1..9 or a decimal is read as mm, like PrintSpeed's ips ---
opt 'GapLength=20';  grep -qx 'GAP 2 mm,0 mm'   "$OUT.txt" || fail "GapLength=20 -> GAP 2 mm"
opt 'GapLength=2';   grep -qx 'GAP 2 mm,0 mm'   "$OUT.txt" || fail "bare GapLength=2 -> GAP 2 mm"
opt 'GapLength=2.5'; grep -qx 'GAP 2.5 mm,0 mm' "$OUT.txt" || fail "GapLength=2.5 -> GAP 2.5 mm"
opt 'MediaTracking=BlackMark GapLength=15'
grep -qx 'BLINE 1.5 mm,0 mm' "$OUT.txt" || fail "GapLength=15 -> BLINE 1.5 mm"
opt 'MediaTracking=PrinterDefault GapLength=20'
grep -qE '^(GAP|BLINE)' "$OUT.txt" && fail "PrinterDefault must send no boundary command"

# --- GapLength guards: under 1 mm or unparsable on a sensor mode would go out
#     as GAP 0 = continuous, switching the sensor off and persisting in the
#     printer -> warn and fall back to 3 mm; the spec caps GAP at 25.4 mm ---
for bad in 'GapLength=0' 'GapLength=abc' 'GapLength=-5' 'MediaTracking=BlackMark GapLength=0'; do
    opt "$bad"
    grep -qE '^(GAP|BLINE) 3 mm,0 mm$' "$OUT.txt" || fail "$bad should fall back to 3 mm"
    grep -q '^WARNING' "$OUT.err" || fail "$bad should warn"
done
opt 'GapLength=999'
grep -qx 'GAP 25.4 mm,0 mm' "$OUT.txt" || fail "GapLength=999 should clamp to 25.4 mm"
grep -q '^WARNING' "$OUT.err" || fail "GapLength=999 should warn"

# --- FixedPitch: GAP 0 like Continuous, but SIZE is label + gap summed in
#     tenths and rounded once (8 dots @300 dpi = 0.68 mm -> 0.7; + 3 mm = 3.7;
#     + 2.5 mm = 3.2; + 0 = 0.7, and 0 is valid here) ---
opt 'MediaTracking=FixedPitch'
grep -qx 'GAP 0 mm,0 mm'    "$OUT.txt" || fail "FixedPitch should emit GAP 0"
grep -qx 'SIZE 1 mm,3.7 mm' "$OUT.txt" || fail "FixedPitch should add the 3 mm default gap to SIZE"
opt 'MediaTracking=FixedPitch GapLength=25'
grep -qx 'SIZE 1 mm,3.2 mm' "$OUT.txt" || fail "FixedPitch GapLength=25 -> SIZE 3.2 mm"
opt 'MediaTracking=FixedPitch GapLength=0'
grep -qx 'SIZE 1 mm,0.7 mm' "$OUT.txt" || fail "FixedPitch GapLength=0 -> bare label height"
grep -q '^WARNING' "$OUT.err" && fail "GapLength=0 is valid on FixedPitch"

echo "smoke test OK"
