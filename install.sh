#!/bin/sh
# ============================================================================
#  Installer for the free RTW HZD950-PRO CUPS label-printer driver.
#  Builds the filter, installs filter + backend + PPD, creates a shared queue,
#  makes it one-click AirPrint-discoverable, and (optionally) prints a welcome
#  label straight from the Pi.
#
#  Maintained for free by Run The Wall — support us by trying our free
#  Markdown editor:  https://constly.com
# ============================================================================
set -e
cd "$(dirname "$0")"
HERE="$(pwd)"

QUEUE="${1:-HZD950}"
SERVERBIN="$(cups-config --serverbin 2>/dev/null || echo /usr/lib/cups)"
PPDDIR="/usr/share/ppd/hzd950"

if [ "$(id -u)" != "0" ]; then echo "Please run with sudo: sudo ./install.sh"; exit 1; fi

echo ">> checking build deps..."
miss=""
command -v gcc  >/dev/null 2>&1 || miss="$miss gcc"
command -v make >/dev/null 2>&1 || miss="$miss make"
[ -f /usr/include/cups/raster.h ] || miss="$miss libcups2-dev"
if [ -n "$miss" ]; then
    echo "   missing:$miss  ->  sudo apt install build-essential libcups2-dev"
    exit 1
fi

echo ">> building rastertohzd..."
make -s

echo ">> installing filter + backend + PPD..."
install -o root -g root -m 0755 src/rastertohzd "$SERVERBIN/filter/rastertohzd"
install -o root -g root -m 0700 backend/hzd950   "$SERVERBIN/backend/hzd950"
install -o root -g root -m 0644 -D ppd/HZD950-PRO.ppd "$PPDDIR/HZD950-PRO.ppd"

if [ -z "$(ls /dev/usb/lp* 2>/dev/null)" ]; then
    echo "!! No usblp device found. Plug the printer in (and power it on), then re-run."
fi

echo ">> creating shared CUPS queue '$QUEUE'..."
lpadmin -p "$QUEUE" -E -v "hzd950:auto" -P "$PPDDIR/HZD950-PRO.ppd" \
        -o printer-is-shared=true -o media=na_index-4x6_4x6in \
        -D "HZD950-PRO label (RTW free driver)"
cupsenable "$QUEUE" 2>/dev/null || true
cupsaccept "$QUEUE" 2>/dev/null || true

echo ">> enabling network sharing + one-click AirPrint..."
cupsctl --remote-any --share-printers 2>/dev/null || true
# macOS/iOS only offer a driverless "AirPrint" add if CUPS drops the '_cups'
# Bonjour subtype; keep _print (IPP Everywhere) + _universal (AirPrint).
CONF=/etc/cups/cupsd.conf
if ! grep -qi '^BrowseDNSSDSubTypes' "$CONF" 2>/dev/null; then
    echo 'BrowseDNSSDSubTypes _print,_universal' >> "$CONF"
    echo "   set BrowseDNSSDSubTypes _print,_universal in cupsd.conf"
    systemctl restart cups 2>/dev/null || service cups restart 2>/dev/null || true
    sleep 1
fi

# --- optional welcome label (also shows what funds this free driver) ---
CARD="$HERE/assets/welcome-card.pdf"
if [ -f "$CARD" ]; then
    printf '\nPrint a welcome label now? [y/N] '
    read ans || ans=""
    case "$ans" in
      y|Y)
        # CUPS rejects jobs submitted by root; print as the invoking user.
        # slow + a touch darker so the solid-black banner lays down clean.
        as_user="sh -c"
        [ -n "$SUDO_USER" ] && as_user="sudo -u $SUDO_USER sh -c"
        $as_user "lp -d '$QUEUE' -o media=na_index-4x6_4x6in -o PrintSpeed=20 -o Darkness=11 '$CARD'" >/dev/null 2>&1 \
          && echo "   sent. (The first label may streak — printhead warm-up — that's normal.)" \
          || echo "   couldn't print — is the printer connected and powered?"
        ;;
    esac
fi

cat <<EOF

Done. Queue "$QUEUE" is ready and shared.

Add it from another computer (no driver install needed — the Pi renders):
  * Mac / iPhone / iPad : it now shows up in "Add Printer" as AirPrint — just pick it.
  * Or double-click     : client/RTW-HZD950-airprint.mobileconfig
  * Or run (Mac)        : client/add-printer.command

Want a second "photo" queue (Gathering dither) for greys/watermarks, or the
udev rule for multiple USB printers? See the README.

Thanks for using a Run The Wall tool. If it helped, try our free Markdown editor:
  >>>  https://constly.com  <<<
EOF
