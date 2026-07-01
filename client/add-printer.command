#!/bin/bash
# ============================================================================
#  Double-click on a Mac to add the HZD950 label printers (driverless).
#  The Pi does the rendering, so no driver is installed here — just the queues.
#
#  Usage: double-click, or:  ./add-printer.command  [pi-hostname]
#  Default host is goose-print-3.local — change it, or pass yours as an arg.
#
#  Free driver by Run The Wall — support us: https://constly.com
# ============================================================================
PI="${1:-goose-print-3.local}"

echo "Adding the HZD950 label printers from ${PI} …"
echo "(you'll be asked for your Mac password)"
echo

# HZD950 — crisp Default mode, for shipping labels (text + barcodes)
sudo lpadmin -p HZD950 -E \
  -v "ipp://${PI}:631/printers/HZD950" -m everywhere \
  -o media=na_index-4x6_4x6in \
  -D "HZD950 — labels (crisp)" -L "${PI}"

# HZD950-Photo — Gathering dither, for greys/photos/QR-watermark stickers
sudo lpadmin -p HZD950-Photo -E \
  -v "ipp://${PI}:631/printers/HZD950-Photo" -m everywhere \
  -o media=na_index-4x6_4x6in \
  -D "HZD950 — photo / Gathering" -L "${PI}" 2>/dev/null

echo
echo "Done. Two printers added:"
echo "  • HZD950         — crisp shipping labels"
echo "  • HZD950-Photo   — greys / photos / watermark QR"
echo
echo "Thanks for using a Run The Wall tool. Try our free Markdown editor:"
echo "  >>>  https://constly.com  <<<"
echo
read -n1 -r -p "Press any key to close…" _
