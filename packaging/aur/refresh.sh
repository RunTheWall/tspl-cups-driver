#!/bin/sh
# ============================================================================
#  Regenerate the AUR PKGBUILD and .SRCINFO for a released version.
#
#    sh packaging/aur/refresh.sh <version> [outdir]
#
#  Downloads that version's release tarball, pins its sha256, and writes both
#  files to <outdir> (default: alongside this script). The three things the
#  release checklist used to ask a human to keep in lockstep -- pkgver, the
#  checksum, and .SRCINFO -- are all derived here from the one input, so they
#  cannot drift apart.
#
#  .SRCINFO needs makepkg, so this only runs fully on Arch; everything else is
#  POSIX. Run from anywhere.
#  SPDX-License-Identifier: MIT
# ============================================================================
set -eu

VER=${1:?usage: refresh.sh <version> [outdir]}
VER=${VER#v}
SRC=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
OUT=${2:-$SRC}
URL="https://github.com/RunTheWall/tspl-cups-driver/archive/refs/tags/v$VER.tar.gz"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP/src.tar.gz" \
    || { echo "refresh: cannot download $URL (is v$VER released?)" >&2; exit 1; }
SHA=$(sha256sum "$TMP/src.tar.gz" | cut -d' ' -f1)
case $SHA in
    ????????????????????????????????????????????????????????????????) ;;
    *) echo "refresh: sha256sum gave no usable digest" >&2; exit 1 ;;
esac

# Write via a temp file so <outdir> may be this directory (sed would otherwise
# truncate the PKGBUILD it is still reading).
sed -e "s/^pkgver=.*/pkgver=$VER/" \
    -e "s/^sha256sums=.*/sha256sums=('$SHA')/" \
    "$SRC/PKGBUILD" > "$TMP/PKGBUILD"
grep -q "^pkgver=$VER$"        "$TMP/PKGBUILD" || { echo "refresh: pkgver not rewritten" >&2; exit 1; }
grep -q "^sha256sums=('$SHA')$" "$TMP/PKGBUILD" || { echo "refresh: sha256sums not rewritten" >&2; exit 1; }

mkdir -p "$OUT"
cp "$TMP/PKGBUILD" "$OUT/PKGBUILD"

if command -v makepkg >/dev/null 2>&1; then
    ( cd "$OUT" && makepkg --printsrcinfo > .SRCINFO )
    grep -q "pkgver = $VER" "$OUT/.SRCINFO" || { echo "refresh: .SRCINFO stale" >&2; exit 1; }
else
    echo "refresh: makepkg not found, .SRCINFO left untouched" >&2
fi

echo "refresh: v$VER sha256=$SHA -> $OUT"
