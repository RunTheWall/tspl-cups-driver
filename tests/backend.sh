#!/bin/sh
# ============================================================================
#  Hardware-free tests for the tspl backend's device resolution.
#
#  find_node() reaches the outside world only through usb_attr() and
#  each_node(), so both are stubbed with a fake USB bus and the real function
#  is sourced straight out of backend/tspl. No printer, no root, no CUPS.
#
#  Run:  sh tests/backend.sh     (CI runs it under each shell it can find)
#  SPDX-License-Identifier: MIT
# ============================================================================
set -eu
cd "$(dirname "$0")/.."
BACKEND=$PWD/backend/tspl
fails=0

# The checks run from a scratch directory seeded with files named after the
# wildcard entries. $KNOWN_IDS is split unquoted, so unless is_known() turns
# pathname expansion off the shell swaps "2d84:*" for a matching filename
# before case ever sees it — and cupsd only chdirs to / when it daemonizes,
# so a hand-run cupsd -f leaves the backend in that shell's directory. With
# the decoys in place the wildcard checks below go red if that guard is ever
# dropped.
scratch=$(mktemp -d)
trap 'cd / && rm -rf "$scratch" || :' EXIT
: > "$scratch/2d84:zz"
: > "$scratch/2d37:zz"
cd "$scratch"

# Bus A: HZD950-PRO, an XP-420B whose serial contains a dash, and a laser that
# must never be auto-matched.
stub_mixed() {
    cat <<'STUB'
usb_attr() {
    case "$1:$2" in
        0:idVendor) echo 0fe6 ;; 0:idProduct) echo 811e ;; 0:serial) echo HERO-01 ;;
        1:idVendor) echo 2d37 ;; 1:idProduct) echo 83d7 ;; 1:serial) echo XP-420B-9Z ;;
        2:idVendor) echo 03f0 ;; 2:idProduct) echo 002a ;; 2:serial) echo LASER1 ;;
    esac
}
each_node() { echo "0 /dev/usb/lp0"; echo "1 /dev/usb/lp1"; echo "2 /dev/usb/lp2"; }
STUB
}

# Bus B: nothing but a laser. auto must resolve to nothing at all.
stub_laser() {
    cat <<'STUB'
usb_attr() {
    case "$1:$2" in
        0:idVendor) echo 03f0 ;; 0:idProduct) echo 002a ;; 0:serial) echo LASER1 ;;
    esac
}
each_node() { echo "0 /dev/usb/lp0"; }
STUB
}

# Buses C and D: a single printer matched only by a vendor-wide wildcard in
# KNOWN_IDS, one per Poskey vendor id. These are the cases that force auto
# through is_known(); without them the suite stays green if a wildcard is
# dropped, or if $k gets quoted so the patterns stop globbing.
stub_poskey37() {
    cat <<'STUB'
usb_attr() {
    case "$1:$2" in
        0:idVendor) echo 2d37 ;; 0:idProduct) echo 83d7 ;; 0:serial) echo XP-420B-9Z ;;
    esac
}
each_node() { echo "0 /dev/usb/lp0"; }
STUB
}
stub_poskey84() {
    cat <<'STUB'
usb_attr() {
    case "$1:$2" in
        0:idVendor) echo 2d84 ;; 0:idProduct) echo b528 ;; 0:serial) echo XP-460B-1A ;;
    esac
}
each_node() { echo "0 /dev/usb/lp0"; }
STUB
}

# Bus E: an LW650XL PRO on its own. The only exact-match entry that sits
# after the wildcards in KNOWN_IDS, so a typo in the token or a dropped entry
# turns this red instead of merging green.
stub_qin() {
    cat <<'STUB'
usb_attr() {
    case "$1:$2" in
        0:idVendor) echo 2e3c ;; 0:idProduct) echo 5757 ;; 0:serial) echo LW650-3F ;;
    esac
}
each_node() { echo "0 /dev/usb/lp0"; }
STUB
}

# The code under test: everything above the discovery-mode marker is pure
# definitions (KNOWN_IDS and the helpers), so it is safe to source whole. The
# stub is applied AFTER it so the fake bus overrides the real sysfs readers.
code() {
    sed -n '1,/^# --- discovery mode/p' "$BACKEND"
}

check() {  # check <shell> <stub> <want> <expected node>
    # "no match" is a normal outcome that also exits non-zero, so only the
    # printed node is treated as the result. The single-quoted find_node call
    # is emitted verbatim into the piped script instead of expanding here.
    # shellcheck disable=SC2016
    got=$({ code; "$2"; echo 'find_node "$1"'; } | "$1" -s "$3" 2>/dev/null) || got=""
    if [ "$got" = "$4" ]; then
        printf '  ok    %-14s -> %s\n' "$3" "${4:-<none>}"
    else
        printf '  FAIL  %-14s -> %s (expected %s)\n' "$3" "${got:-<none>}" "${4:-<none>}"
        fails=$((fails + 1))
    fi
}

for shell in sh dash bash ksh; do
    command -v "$shell" >/dev/null 2>&1 || { echo "-- $shell: not installed, skipped"; continue; }
    echo "-- $shell"

    # auto picks the first known TSPL printer, in any case, and never the laser
    check "$shell" stub_mixed auto         /dev/usb/lp0
    check "$shell" stub_mixed AUTO         /dev/usb/lp0
    check "$shell" stub_laser auto         ""

    # auto finds a printer that only a vendor-wide wildcard can match. This is
    # the case issue #4 reported, and the only coverage KNOWN_IDS globbing has.
    check "$shell" stub_poskey37 auto      /dev/usb/lp0
    check "$shell" stub_poskey84 auto      /dev/usb/lp0

    # an exact-match id listed after the wildcards still resolves
    check "$shell" stub_qin auto           /dev/usb/lp0

    # a USB id pins, written with a dash (the spelling CUPS accepts)
    check "$shell" stub_mixed 0fe6-811e    /dev/usb/lp0
    check "$shell" stub_mixed 2d37-83d7    /dev/usb/lp1
    check "$shell" stub_mixed 0FE6-811E    /dev/usb/lp0

    # the legacy colon spelling still resolves, for queues that already use it
    check "$shell" stub_mixed 0fe6:811e    /dev/usb/lp0
    check "$shell" stub_mixed 2d37:83d7    /dev/usb/lp1

    # serials match as typed, including one that contains a dash
    check "$shell" stub_mixed XP-420B-9Z   /dev/usb/lp1
    check "$shell" stub_mixed HERO-01      /dev/usb/lp0

    # an unknown printer can still be pinned explicitly, by id or serial
    check "$shell" stub_mixed 03f0-002a    /dev/usb/lp2
    check "$shell" stub_mixed LASER1       /dev/usb/lp2

    # nothing invented out of thin air
    check "$shell" stub_mixed 1234-5678    ""
    check "$shell" stub_mixed nosuchthing  ""
done

[ "$fails" -eq 0 ] || { echo "$fails backend test(s) failed" >&2; exit 1; }
echo "backend tests OK"
