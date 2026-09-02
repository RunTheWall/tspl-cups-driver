#!/bin/sh
# ============================================================================
#  KNOWN_IDS in backend/tspl has three hand-kept mirrors: the rule lines in
#  udev/99-tspl-label.rules, the id inventory in that file's header, and the
#  README's printer table. This checks every entry is in all three, so an id
#  that lands in the backend alone (auto-detected, but no /dev/usb/tspl-label
#  symlink and no row telling owners it is supported) fails CI instead of
#  drifting quietly. Matches are anchored to a live rule line, a header
#  entry and a table row; a mention in prose or a commented-out rule does
#  not count.
#
#  Run:  sh tests/ids.sh
#  SPDX-License-Identifier: MIT
# ============================================================================
set -eu
set -f   # the list holds glob patterns such as 2d84:*; never expand them
cd "$(dirname "$0")/.."
RULES=udev/99-tspl-label.rules
fails=0

# Everything between the quotes, whatever follows them on the line.
ids=$(sed -n 's/^KNOWN_IDS="\([^"]*\)".*$/\1/p' backend/tspl)
[ -n "$ids" ] || { echo "KNOWN_IDS not found in backend/tspl" >&2; exit 1; }

ok()  { printf '  ok    %-10s %s\n' "$1" "$2"; }
bad() { printf '  FAIL  %-10s %s\n' "$1" "$2"; fails=$((fails + 1)); }

for id in $ids; do
    vid=${id%%:*}; pid=${id#*:}

    # a live rule line: idVendor plus idProduct for an exact id, idVendor
    # alone for a vendor-wide one (key order and spacing are free)
    if [ "$pid" = '*' ]; then
        if grep "^ATTRS.*idVendor}==\"$vid\"" "$RULES" | grep -qv idProduct; then
            ok "$id" "udev rule"
        else
            bad "$id" "no bare idVendor rule in $RULES"
        fi
    elif grep "^ATTRS.*idVendor}==\"$vid\"" "$RULES" | grep -q "idProduct}==\"$pid\""; then
        ok "$id" "udev rule"
    else
        bad "$id" "no idVendor+idProduct rule in $RULES"
    fi

    # the header inventory people read when they copy the rules file
    if grep -qF -- "#   $id " "$RULES"; then
        ok "$id" "udev header"
    else
        bad "$id" "not listed in the header of $RULES"
    fi

    # a printer-table row: the exact id, or any product on a wildcarded vendor
    if [ "$pid" = '*' ]; then row="\`$vid"; else row="\`$id\`"; fi
    if grep -q "^|.*$row" README.md; then
        ok "$id" "README row"
    else
        bad "$id" "no printer-table row in README.md"
    fi
done

[ "$fails" -eq 0 ] || { echo "$fails id mirror check(s) failed" >&2; exit 1; }
echo "known ids mirrored OK"
