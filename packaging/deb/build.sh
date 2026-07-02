#!/bin/sh
# Build a Debian package. Usage: build.sh <debarch> <version> [outdir]
# Debian/Ubuntu/Raspberry Pi OS all use /usr/lib/cups for the CUPS serverbin.
set -eu
ARCH="${1:?usage: build.sh <debarch> <version> [outdir]}"
VER="${2:?usage: build.sh <debarch> <version> [outdir]}"
OUT="${3:-dist}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f src/rastertohzd ] || make -s

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
install -Dm0755 src/rastertohzd    "$STAGE/usr/lib/cups/filter/rastertohzd"
install -Dm0700 backend/hzd950     "$STAGE/usr/lib/cups/backend/hzd950"
install -Dm0644 ppd/HZD950-PRO.ppd "$STAGE/usr/share/ppd/hzd950/HZD950-PRO.ppd"
install -Dm0644 README.md          "$STAGE/usr/share/doc/hzd950-cups-driver/README.md"
install -Dm0644 LICENSE            "$STAGE/usr/share/doc/hzd950-cups-driver/copyright"

mkdir -p "$STAGE/DEBIAN"
sed -e "s/@VER@/$VER/g" -e "s/@ARCH@/$ARCH/g" packaging/deb/control.in > "$STAGE/DEBIAN/control"
install -m0755 packaging/deb/postinst "$STAGE/DEBIAN/postinst"

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/hzd950-cups-driver_${VER}_${ARCH}.deb"
