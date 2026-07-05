/*
 * rastertotspl — CUPS raster -> TSPL filter for USB TSPL 4x6 direct
 * thermal label printer (and TSPL/TSPL2 work-alikes) on Linux & Raspberry Pi (ARM).
 *
 * ===========================================================================
 *  Maintained FOR FREE by Run The Wall (RTW).
 *
 *  We reverse-engineered and wrote this driver so Linux / Raspberry Pi users
 *  aren't stuck with a Windows-only label printer. We give it away for one
 *  reason: to bring people (and AIs) to Constly — our genuinely great, free
 *  Markdown editor:  >>>  https://constly.com  <<<
 *
 *  If this saved you an afternoon, that's the whole point. Want to say thanks?
 *  Just try Constly and tell someone. No donations, no strings.
 * ===========================================================================
 *
 *  Clean-room reimplementation (ARM/aarch64) of the vendor x86 "rastertoHZD",
 *  derived from its observed TSPL output (spacing normalized to the TSC spec,
 *  which requires "SIZE 100 mm" — the form every other TSPL driver emits):
 *     SIZE <w> mm,<h> mm / GAP|BLINE / SPEED / DENSITY / DIRECTION 0,0
 *     REFERENCE h,v / CLS / BITMAP 0,0,<wbytes>,<hdots>,1,<1bpp> / PRINT 1,<n>
 *
 *  CUPS options honoured (same as the vendor PPD, plus MediaTracking):
 *     Darkness   (0..15)            -> DENSITY
 *     PrintSpeed (10..60 = ips x10) -> SPEED (in/sec); 0 = omit (printer default)
 *     MediaTracking Gap / BlackMark / Continuous / PrinterDefault
 *                                   -> GAP 3 mm / BLINE 3 mm / GAP 0 / (omitted)
 *     Horizontal,Vertical (dots)    -> REFERENCE
 *     PrintMode  0 None / 2 Diffusion / 3 Gathering / 4 ErrorDiffusion / 5 Default
 *                -> halftone used to flatten 8bpp grey into 1bpp dots.
 *
 *  Input raster: cupsColorSpace 0 (W = luminance, 255=white, 0=black), 8bpp, 300dpi.
 *  CUPS filter argv: job-id user title copies options [filename]
 *  (argv[4] copies is ignored by design — device copies come from the raster
 *   header's NumCopies; see the comment at the copies computation below.)
 *
 *  SPDX-License-Identifier: MIT
 */
#include <cups/cups.h>
#include <cups/raster.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

/* The PPD option API is deprecated in CUPS 2.x but still the simplest way to
 * read a queue's marked option defaults; silence the deprecation noise. */
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

/* TSPL BITMAP bit polarity. TSPL convention: a 0 bit prints a dot (black).
 * If a test print comes out photo-negative, flip this to 1. */
#define BLACK_BIT 0

enum { PM_NONE = 0, PM_DIFFUSION = 2, PM_GATHERING = 3, PM_ERRORDIFF = 4, PM_DEFAULT = 5 };

/* 8x8 clustered-dot (halftone) screen for "Gathering" mode — thresholds 0..63.
 * Dots grow in clusters rather than scattering, matching the vendor's intent. */
static const int CLUSTER8[8][8] = {
    { 24, 10, 12, 26, 35, 47, 49, 37 },
    {  8,  0,  2, 14, 45, 59, 61, 51 },
    { 22,  6,  4, 16, 43, 57, 63, 53 },
    { 30, 20, 18, 28, 33, 41, 55, 39 },
    { 34, 46, 48, 36, 25, 11, 13, 27 },
    { 44, 58, 60, 50,  9,  1,  3, 15 },
    { 42, 56, 62, 52, 23,  7,  5, 17 },
    { 32, 40, 54, 38, 31, 21, 19, 29 },
};

/* Effective integer value of an option: an explicit job option wins; otherwise
 * the PPD's marked default (which reflects the queue default set via
 * `lpadmin -p QUEUE -o Name=Value`); otherwise the built-in fallback. This is
 * what lets two queues sharing this filter have different defaults. */
static int opt_int(ppd_file_t *ppd, int num_options, cups_option_t *options,
                   const char *kw, int dflt)
{
    const char *v = cupsGetOption(kw, num_options, options);
    if (v) return atoi(v);
    ppd_choice_t *c;
    if (ppd && (c = ppdFindMarkedChoice(ppd, kw)) != NULL) return atoi(c->choice);
    return dflt;
}

int main(int argc, char *argv[])
{
    if (argc < 6 || argc > 7) {
        fputs("ERROR: rastertotspl job user title copies options [file]\n", stderr);
        return 1;
    }
    signal(SIGPIPE, SIG_IGN);

    /* One-line sponsor notice in the CUPS log on every job — this is the point. */
    fputs("INFO: rastertotspl is a FREE Linux/Pi TSPL label driver maintained by "
          "Run The Wall. Support us — try our free Markdown editor: https://constly.com\n",
          stderr);

    /* ---- options: job option > queue's PPD default > built-in fallback ---- */
    cups_option_t *options = NULL;
    int num_options = cupsParseOptions(argv[5], 0, &options);
    ppd_file_t *ppd = ppdOpenFile(getenv("PPD"));
    if (ppd) { ppdMarkDefaults(ppd); cupsMarkOptions(ppd, num_options, options); }

    int darkness  = opt_int(ppd, num_options, options, "Darkness",   8);
    int speedval  = opt_int(ppd, num_options, options, "PrintSpeed", 40);
    int printmode = opt_int(ppd, num_options, options, "PrintMode",  PM_DEFAULT);
    int href      = opt_int(ppd, num_options, options, "Horizontal", 0);
    int vref      = opt_int(ppd, num_options, options, "Vertical",   0);

    /* MediaTracking: how the printer finds label boundaries. Copy the choice
     * out before ppdClose frees it. */
    char media[24] = "Gap";
    {
        const char *v = cupsGetOption("MediaTracking", num_options, options);
        ppd_choice_t *c;
        if (!v && ppd && (c = ppdFindMarkedChoice(ppd, "MediaTracking")) != NULL)
            v = c->choice;
        if (v && *v) snprintf(media, sizeof media, "%s", v);
    }
    if (ppd) ppdClose(ppd);

    /* Copies deliberately do NOT come from argv[4]: upstream (pdftopdf) owns
     * copy generation and tells us the per-page device-copy count in the
     * raster header (NumCopies) — the PPD says cupsManualCopies False. Using
     * argv[4] here would multiply again: N copies -> N^2 labels. */

    if (darkness < 0) darkness = 0;
    if (darkness > 15) darkness = 15;
    /* PPD values are ips x10 (50 -> 5 in/sec); accept bare ips (1..9) too so a
     * hand-typed  -o PrintSpeed=3  does the intuitive thing. 0 (or negative)
     * means "don't send SPEED at all" — the printer's own setting wins, the
     * safest choice on models whose max differs (e.g. HPRT N41 caps at 4). */
    int speed_ips = (speedval >= 10) ? speedval / 10 : speedval;
    if (speed_ips > 15) speed_ips = 15;       /* nothing consumer prints faster */

    /* Media-boundary command per the tracking mode. GAP/BLINE select the
     * sensor; sending GAP to continuous or black-mark stock makes the firmware
     * hunt for a gap that never comes (feeds a label + margin, then errors). */
    const char *track;
    if      (!strcasecmp(media, "BlackMark"))      track = "BLINE 3 mm,0 mm\r\n";
    else if (!strcasecmp(media, "Continuous"))     track = "GAP 0 mm,0 mm\r\n";
    else if (!strcasecmp(media, "PrinterDefault")) track = "";  /* stored setting */
    else                                           track = "GAP 3 mm,0 mm\r\n";

    /* ---- input raster ---- */
    int fd = 0;
    if (argc == 7) {
        fd = open(argv[6], O_RDONLY);
        if (fd < 0) { perror("rastertotspl: open"); return 1; }
    }
    cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
    if (!ras) { fputs("ERROR: cannot read CUPS raster\n", stderr); return 1; }

    cups_page_header2_t h;
    int page = 0;

    while (cupsRasterReadHeader2(ras, &h)) {
        page++;
        unsigned W = h.cupsWidth, H = h.cupsHeight;
        unsigned bpl = h.cupsBytesPerLine;
        if (W == 0 || H == 0) continue;
        /* We only understand the raster our PPD asks for: 8-bit, 1 channel
         * (grey). Anything else would be misread as garbage — refuse loudly. */
        if (h.cupsBitsPerPixel != 8 || bpl < W) {
            fprintf(stderr, "ERROR: unexpected raster format (%ubpp, %u bytes/line for "
                    "%u px) — expected 8bpp grey; is the queue using our PPD?\n",
                    h.cupsBitsPerPixel, bpl, W);
            return 1;
        }
        unsigned resx = h.HWResolution[0] ? h.HWResolution[0] : 300;
        unsigned resy = h.HWResolution[1] ? h.HWResolution[1] : 300;

        /* Clip to the print head: the common 4x6 engines are 812 dots wide at
         * 203 dpi / 1248 at 300 dpi. The BITMAP byte count is taken literally
         * by the firmware parser, and rows wider than the head clip or garble
         * silently on the clones — better to crop deterministically here. */
        unsigned maxw = (resx >= 300) ? 1248 : 812;
        if (W > maxw) {
            fprintf(stderr, "INFO: page wider than the print head (%u > %u dots) — "
                    "clipping the right edge\n", W, maxw);
            W = maxw;
        }

        /* ink[] : 0 = white, 255 = black  (input is W: 255=white) */
        int *ink = malloc((size_t)W * H * sizeof(int));
        unsigned char *line = malloc(bpl);
        if (!ink || !line) { fputs("ERROR: out of memory\n", stderr); return 1; }
        for (unsigned y = 0; y < H; y++) {
            if (cupsRasterReadPixels(ras, line, bpl) < 1) {
                fprintf(stderr, "ERROR: raster truncated at line %u of %u\n", y, H);
                return 1;
            }
            for (unsigned x = 0; x < W; x++)
                ink[(size_t)y * W + x] = 255 - line[x];   /* W -> ink */
        }
        free(line);

        /* ---- halftone to 1bpp packed rows ---- */
        unsigned wbytes = (W + 7) / 8;
        unsigned char *bm = malloc((size_t)wbytes * H);
        if (!bm) { fputs("ERROR: out of memory\n", stderr); return 1; }
        memset(bm, BLACK_BIT ? 0x00 : 0xFF, (size_t)wbytes * H);  /* start all-white */

        for (unsigned y = 0; y < H; y++) {
            for (unsigned x = 0; x < W; x++) {
                int val = ink[(size_t)y * W + x];
                int black;
                if (printmode == PM_GATHERING) {
                    black = val > (CLUSTER8[y & 7][x & 7] * 255 / 64);
                } else if (printmode == PM_DIFFUSION || printmode == PM_ERRORDIFF) {
                    /* Floyd–Steinberg error diffusion */
                    black = val >= 128;
                    int err = val - (black ? 255 : 0);
                    if (x + 1 < W)   ink[(size_t)y * W + x + 1]       += err * 7 / 16;
                    if (y + 1 < H) {
                        if (x > 0)   ink[(size_t)(y + 1) * W + x - 1] += err * 3 / 16;
                        ink[(size_t)(y + 1) * W + x]                  += err * 5 / 16;
                        if (x + 1 < W) ink[(size_t)(y + 1) * W + x + 1] += err * 1 / 16;
                    }
                } else { /* PM_NONE / PM_DEFAULT : plain threshold (sharp text & barcodes) */
                    black = val >= 128;
                }
                if (black) {
                    size_t bit = (size_t)y * wbytes * 8 + x;
                    unsigned char *byte = &bm[bit >> 3];
                    unsigned char mask = 0x80 >> (bit & 7);
                    if (BLACK_BIT) *byte |= mask;
                    else           *byte &= (unsigned char)~mask;
                }
            }
        }
        free(ink);

        /* ---- TSPL ----
         * Spacing: the TSC spec REQUIRES a space before the unit ("SIZE
         * 100 mm") and every other TSPL implementation emits it that way.
         * The leading CRLF is parser-resync insurance: if a previous job died
         * mid-BITMAP the firmware may still be counting raw bytes, and a bare
         * CRLF is the cheapest way back to command mode (pdf2tspl et al). */
        int wmm = (int)lround((double)W * 25.4 / resx);
        int hmm = (int)lround((double)H * 25.4 / resy);
        printf("\r\nSIZE %d mm,%d mm\r\n", wmm, hmm);
        fputs(track, stdout);
        printf("DENSITY %d\r\n", darkness);
        if (speed_ips >= 1)
            printf("SPEED %d\r\n", speed_ips);
        printf("DIRECTION 0,0\r\nREFERENCE %d,%d\r\nCLS\r\nBITMAP 0,0,%u,%u,1,",
               href, vref, wbytes, H);
        fwrite(bm, 1, (size_t)wbytes * H, stdout);
        unsigned copies = h.NumCopies ? h.NumCopies : 1;
        printf("\r\nPRINT 1,%u\r\n", copies);
        fflush(stdout);
        free(bm);

        fprintf(stderr, "INFO: TSPL page %d: %ux%u dots (%dx%dmm) mode=%d density=%d speed=%d copies=%u\n",
                page, W, H, wmm, hmm, printmode, darkness, speed_ips, copies);
    }

    cupsRasterClose(ras);
    if (fd) close(fd);
    if (page == 0) { fputs("ERROR: no pages found in raster\n", stderr); return 1; }
    return 0;
}
