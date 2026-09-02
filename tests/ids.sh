#!/bin/sh
# ============================================================================
#  KNOWN_IDS in backend/tspl has two hand-kept mirrors: the udev rules and
#  the README's printer table. This checks every entry is in both, so an id
#  that lands in the backend alone (auto-detected, but no /dev/usb/tspl-label
#  symlink and no row telling owners it is supported) fails CI instead of
#  drifting quietly.
#
#  Run:  sh tests/ids.sh
#  SPDX-License-Identifier: MIT
# ============================================================================
set -eu
set -f   # the list holds glob patterns such as 2d84:*; never expand them
cd "$(dirname "$0")/.."
fails=0

ids=$(sed -n 's/^KNOWN_IDS="\(.*\)"$/\1/p' backend/tspl)
[ -n "$ids" ] || { echo "KNOWN_IDS not found in backend/tspl" >&2; exit 1; }

for id in $ids; do
    vid=${id%%:*}; pid=${id#*:}
    if [ "$pid" = '*' ]; then
        # a vendor-wide entry needs a bare idVendor rule and a mention of the vid
        rule="ATTRS{idVendor}==\"$vid\", GOTO=\"tspl_link\""
        doc="\`$vid\`"
    else
        rule="ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", GOTO=\"tspl_link\""
        doc="\`$id\`"
    fi
    if grep -qF -- "$rule" udev/99-tspl-label.rules; then
        printf '  ok    %-10s udev rule\n' "$id"
    else
        printf '  FAIL  %-10s no rule in udev/99-tspl-label.rules\n' "$id"
        fails=$((fails + 1))
    fi
    if grep -qF -- "$doc" README.md; then
        printf '  ok    %-10s README\n' "$id"
    else
        printf '  FAIL  %-10s not mentioned in README.md\n' "$id"
        fails=$((fails + 1))
    fi
done

[ "$fails" -eq 0 ] || { echo "$fails id mirror check(s) failed" >&2; exit 1; }
echo "known ids mirrored OK"
