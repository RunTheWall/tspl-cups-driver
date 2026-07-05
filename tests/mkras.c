/*
 * mkras — emit a tiny synthetic CUPS raster on stdout for testing rastertotspl
 * without a printer (or any of CUPS beyond libcups).
 *
 * Two pages, 12x8 px (so rows need pad bits), 8bpp grey (W: 255=white), 300 dpi:
 *   page 1: top row black, rest white, NumCopies 1 -> packing/polarity/padding
 *   page 2: all mid-grey (128), NumCopies 4        -> halftone + device copies
 *
 * Part of the free RTW TSPL driver — https://constly.com
 * SPDX-License-Identifier: MIT
 */
#include <cups/raster.h>
#include <string.h>

int main(void)
{
    cups_raster_t *r = cupsRasterOpen(1, CUPS_RASTER_WRITE);
    if (!r) return 1;

    cups_page_header2_t h;
    memset(&h, 0, sizeof h);
    h.cupsWidth = 12; h.cupsHeight = 8; h.cupsBytesPerLine = 12;
    h.cupsBitsPerColor = 8; h.cupsBitsPerPixel = 8; h.cupsNumColors = 1;
    h.cupsColorSpace = CUPS_CSPACE_W;
    h.HWResolution[0] = 300; h.HWResolution[1] = 300;

    unsigned char row[12];
    for (int page = 0; page < 2; page++) {
        h.NumCopies = page == 0 ? 1 : 4;
        if (!cupsRasterWriteHeader2(r, &h)) return 1;
        for (int y = 0; y < 8; y++) {
            if (page == 0) memset(row, y == 0 ? 0 : 255, sizeof row);
            else           memset(row, 128, sizeof row);
            if (cupsRasterWritePixels(r, row, sizeof row) < 1) return 1;
        }
    }
    cupsRasterClose(r);
    return 0;
}
