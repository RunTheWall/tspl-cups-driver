#!/bin/sh
# ============================================================================
#  Installer for the free RTW TSPL label-printer CUPS driver.
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
PPDDIR="/usr/share/ppd/tspl"

# CUPS server binary dir varies by distro: /usr/lib/cups (Debian/Arch),
# /usr/libexec/cups (Fedora/RHEL), /usr/lib64/cups (some). Trust cups-config,
# else probe the known locations.
SERVERBIN="$(cups-config --serverbin 2>/dev/null)"
[ -d "$SERVERBIN/backend" ] || SERVERBIN=""
if [ -z "$SERVERBIN" ]; then
    for d in /usr/lib/cups /usr/libexec/cups /usr/lib64/cups; do
        [ -d "$d/backend" ] && { SERVERBIN="$d"; break; }
    done
fi
[ -n "$SERVERBIN" ] || SERVERBIN=/usr/lib/cups

if [ "$(id -u)" != "0" ]; then echo "Please run with sudo: sudo ./install.sh"; exit 1; fi

REPO_URL="https://github.com/RunTheWall/tspl-cups-driver"

dep_hint() {
    echo "   install a C compiler, make, and the CUPS dev headers:"
    if   command -v apt-get >/dev/null 2>&1; then echo "   ->  sudo apt install build-essential libcups2-dev"
    elif command -v dnf     >/dev/null 2>&1; then echo "   ->  sudo dnf install gcc make cups-devel"
    elif command -v yum     >/dev/null 2>&1; then echo "   ->  sudo yum install gcc make cups-devel"
    elif command -v pacman  >/dev/null 2>&1; then echo "   ->  sudo pacman -S --needed base-devel cups"
    elif command -v zypper  >/dev/null 2>&1; then echo "   ->  sudo zypper install gcc make cups-devel"
    elif command -v apk     >/dev/null 2>&1; then echo "   ->  sudo apk add build-base cups-dev"
    else echo "   ->  (your package manager) install: gcc make cups-devel"
    fi
}
deb_arch() {
    case "$(uname -m)" in
        x86_64|amd64)               echo amd64 ;;
        aarch64|arm64)              echo arm64 ;;
        armv7l|armv6l|armv8l|armhf) echo armhf ;;
        *)                          echo ""    ;;
    esac
}

# Get the filter binary: build from source when we can, else fetch a prebuilt
# one from the GitHub release — so a compiler is NOT required.
BIN=""
have_cc=0;  { command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; } && have_cc=1
have_hdr=0; { [ -f /usr/include/cups/raster.h ] || cups-config --cflags >/dev/null 2>&1; } && have_hdr=1
if [ "$have_cc" = 1 ] && [ "$have_hdr" = 1 ]; then
    echo ">> building rastertotspl from source..."
    make -s && [ -f src/rastertotspl ] && BIN=src/rastertotspl
fi
if [ -z "$BIN" ]; then
    A="$(deb_arch)"
    if [ -n "$A" ] && command -v curl >/dev/null 2>&1; then
        echo ">> no compiler/headers here — fetching prebuilt rastertotspl-$A ..."
        tmp="/tmp/rastertotspl.$$"
        if curl -fsSL "$REPO_URL/releases/latest/download/rastertotspl-$A" -o "$tmp" && [ -s "$tmp" ]; then
            chmod +x "$tmp"
            rc=0; "$tmp" >/dev/null 2>&1 || rc=$?  # 126/127 == can't exec (wrong libc/arch);
                                                   # (|| keeps set -e from killing us: the
                                                   # no-args usage check exits 1 by design)
            if [ "$rc" != 126 ] && [ "$rc" != 127 ]; then BIN="$tmp"
            else echo "   that prebuilt won't run here — falling back to a source build."; rm -f "$tmp"; fi
        else echo "   couldn't download a prebuilt (no release asset for $A yet?)."; fi
    fi
fi
if [ -z "$BIN" ]; then
    echo "!! Couldn't build or fetch the filter binary."
    dep_hint
    exit 1
fi

echo ">> installing filter + backend + PPD..."
install -o root -g root -m 0755 "$BIN" "$SERVERBIN/filter/rastertotspl"
install -o root -g root -m 0700 backend/tspl   "$SERVERBIN/backend/tspl"
install -o root -g root -m 0644 -D ppd/tspl-label.ppd "$PPDDIR/tspl-label.ppd"

if [ -z "$(ls /dev/usb/lp* 2>/dev/null)" ]; then
    echo "!! No usblp device found. Plug the printer in (and power it on), then re-run."
fi

echo ">> creating shared CUPS queue '$QUEUE'..."
lpadmin -p "$QUEUE" -E -v "tspl://auto" -P "$PPDDIR/tspl-label.ppd" \
        -o printer-is-shared=true -o media=na_index-4x6_4x6in \
        -D "TSPL label printer (RTW free driver)"
cupsenable "$QUEUE" 2>/dev/null || true
cupsaccept "$QUEUE" 2>/dev/null || true

echo ">> enabling network sharing + one-click AirPrint..."
# --share-printers covers same-LAN clients (the normal AirPrint case).
# --remote-any additionally allows clients from ANY network (needed for the
# cross-subnet setups the .mobileconfig supports) — if your Pi is reachable
# from untrusted networks, tighten it later with:  sudo cupsctl --no-remote-any
cupsctl --remote-any --share-printers 2>/dev/null || true
# macOS/iOS only offer a driverless "AirPrint" add if CUPS drops the '_cups'
# Bonjour subtype; keep _print (IPP Everywhere) + _universal (AirPrint).
CONF=/etc/cups/cupsd.conf
if ! grep -qi '^BrowseDNSSDSubTypes' "$CONF" 2>/dev/null; then
    echo 'BrowseDNSSDSubTypes _print,_universal' >> "$CONF"
    echo "   set BrowseDNSSDSubTypes _print,_universal in cupsd.conf"
    systemctl restart cups 2>/dev/null || systemctl restart cupsd 2>/dev/null \
      || service cups restart 2>/dev/null || service cupsd restart 2>/dev/null || true
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
        # slowest speed + max darkness so the solid-black banner lays down solid.
        as_user="sh -c"
        [ -n "$SUDO_USER" ] && as_user="sudo -u $SUDO_USER sh -c"
        $as_user "lp -d '$QUEUE' -o media=na_index-4x6_4x6in -o PrintSpeed=10 -o Darkness=15 '$CARD'" >/dev/null 2>&1 \
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
