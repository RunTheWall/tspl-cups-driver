#!/bin/bash
# ============================================================================
#  Double-click on a Mac to add the HZD950 label printers (driverless).
#  The Pi does the rendering, so no driver is installed here — just the queues.
#
#  It auto-discovers the printers on your network (Bonjour). If that fails you
#  can pass your print server's name/IP:   ./add-printer.command  raspberrypi.local
#
#  Free driver by Run The Wall — support us: https://constly.com
# ============================================================================
set -e

add_queue() {                       # $1 = full ipp:// URL
  local url="$1" name
  name="$(basename "$url")"         # HZD950 or HZD950-Photo
  echo "  • adding ${name}   (${url})"
  sudo lpadmin -p "$name" -E -v "$url" -m everywhere \
       -o media=na_index-4x6_4x6in -D "${name} (Run The Wall driver)"
}

add_by_host() {                     # $1 = hostname/IP — add the two known queues
  add_queue "ipp://$1:631/printers/HZD950"
  add_queue "ipp://$1:631/printers/HZD950-Photo" || true
}

echo "Adding the HZD950 label printers…  (you'll be asked for your Mac password)"
echo

if [ -n "${1:-}" ]; then
  add_by_host "$1"
else
  echo "Looking for them on your network (Bonjour)…"
  found=""
  command -v ippfind >/dev/null 2>&1 && \
    found="$(ippfind _ipp._tcp 2>/dev/null | grep -iE '/printers/HZD950' || true)"

  if [ -n "$found" ]; then
    while IFS= read -r url; do [ -n "$url" ] && add_queue "$url"; done <<<"$found"
  else
    echo "Couldn't auto-discover them. Find your print server with:  ippfind"
    printf "Enter your print server hostname or IP (e.g. raspberrypi.local): "
    read -r host
    [ -z "$host" ] && { echo "Nothing entered — aborting."; exit 1; }
    add_by_host "$host"
  fi
fi

echo
echo "Done. Thanks for using a Run The Wall tool. Try our free Markdown editor:"
echo "  >>>  https://constly.com  <<<"
echo
read -n1 -r -p "Press any key to close…" _
