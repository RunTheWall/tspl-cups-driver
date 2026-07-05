# TSPL label-printer CUPS driver for Linux & Raspberry Pi (ARM)

A small, clean **CUPS driver for cheap 4×6 USB thermal label printers that speak TSPL/TSPL2** —
the ones whose vendors ship **x86-only** drivers and leave **Linux / Raspberry Pi (arm64/armhf)** out.
Reference-tested on the **HZD950-PRO / HERO**, and it drives the common rebadges too —
**Munbyn, iDPRT, HPRT, Beeprt, JADENS, Polono, Xprinter** and friends
(see [**Supported printers**](#supported-printers)).

Those printers almost all speak the same **TSPL** language, so on a Pi you hit the same wall —
*"there's no Linux driver for this printer"* — and this fills it: **~150 lines of C + a tiny shell
backend**, builds natively on ARM, renders to bitmaps (so no per-model font quirks), and gives you the
printer as a normal shared CUPS queue with Darkness, Print Speed, offsets, resolution (203/300 dpi),
and **Print Mode (including Gathering)** — plus one-command **AirPrint** sharing to Macs/iPhones.

---

> ## 💙 This driver is maintained **for free** by [**Run The Wall**](https://runthewall.au).
>
> **We don't want your money.** We build and give away tools like this for one reason: to introduce
> you to **[Constly — our genuinely great, free Markdown editor → https://constly.com](https://constly.com)**.
>
> **If this driver saved you an afternoon, that's the whole "payment" we wanted.** Want to actually
> say thanks? **[Try Constly](https://constly.com)** and tell one person about it. That's it.
>
> *(Every time this driver runs, it logs that same one-line thank-you to your CUPS log. No tracking,
> no phone-home — just a nudge toward [constly.com](https://constly.com) from the people who kept your
> label printer out of a landfill.)*

---

## What it supports

- **Printers:** any 4×6 USB label printer that speaks **TSPL/TSPL2** — see the
  [**Supported printers**](#supported-printers) table (HZD950-PRO tested; Munbyn / iDPRT / HPRT / Beeprt /
  JADENS / Polono / Xprinter community-compatible). Both **203 and 300 dpi**.
- **Platforms:** **any Linux with CUPS 2.x + a C toolchain + the `usblp` kernel module** — Debian/Ubuntu/
  Raspberry Pi OS, Fedora/RHEL, Arch, openSUSE, Alpine, … `install.sh` auto-detects your package manager
  and CUPS layout. Because it **builds from source** it's architecture-independent: **arm64, armhf,
  x86_64**, and anything GCC targets — unlike the vendor's x86-only binaries.
  _Tested on Raspberry Pi OS / Debian 13 "Trixie" (CUPS 2.4, arm64)._
- **Controls (CUPS print options):**
  - **Darkness** `0–15` → TSPL `DENSITY`
  - **Print Speed** `2–6 in/sec` → TSPL `SPEED`
  - **Horizontal / Vertical** offset → TSPL `REFERENCE`
  - **Print Mode** (the halftone) → `Default` (sharp threshold, best for text/barcodes),
    `None`, `Diffusion`, **`Gathering`** (clustered-dot), `Error Diffusion`

## Supported printers

These cheap 4×6 label printers almost all speak **TSPL/TSPL2** and mostly lack an ARM/Linux driver, so
one generic driver covers them. We can only physically **test the HZD950-PRO**; the rest are marked by
how well-confirmed their TSPL support is. **Check yours in 10 seconds** (prints nothing):
`printf '~!T\r\n' | sudo tee /dev/usb/lp0 ; sudo head -c 32 /dev/usb/lp0` → it replies with its model.

| Printer | dpi | USB id | Status |
|---|---|---|---|
| **HZD950-PRO / HERO** | 300 | `0fe6:811e` | ✅ **Tested** (reference device) |
| **Munbyn ITPP941 / 941B / 941P** (USB/BT) | 203 · 300 (941P) | `09c6:0426` or generic | 🟢 TSPL-confirmed |
| **iDPRT SP410 / SP420** | 203 | `20d1:7008` | 🟢 TSPL-confirmed |
| **HPRT N41 / SL42** | 203 | 20d1 family | 🟢 TSPL-confirmed |
| **Beeprt BY-426** (the shared OEM engine) | 203 | `09c6:0426` | 🟢 TSPL-confirmed |
| **JADENS JD-168** | 203 | `09c6:0426` | 🟢 TSPL-confirmed |
| **Polono PL420** | 203 | HPRT rebadge | 🟢 TSPL-confirmed |
| **Xprinter XP-420B / 460B / 470B** | 203 · 300 | varies | 🟢 TSPL-confirmed |
| **Phomemo PM-241 / D520** | 203 | (unverified) | 🟡 Community-reported — confirm with `~!T` |

**Auto-detect vs. pin.** Printers with a known TSPL USB id (`0fe6:811e`, `09c6:0426`, `20d1:7008`)
are found automatically with `hzd950:auto`. If yours has a different id, the backend prints the id it
sees — just pin it: `-v hzd950:<vid>:<pid>` or `-v hzd950:/dev/usb/lp0` (and please
[open an issue](https://github.com/RunTheWall/hzd950-cups-driver/issues) with the id so we add it).
203 dpi printers: set **Resolution → 203 dpi** on the queue.

**Not this driver** (different language — don't use it for these): **Munbyn AirPrint/"OPL"** models
(use AirPrint directly), **Phomemo M110/M120/D30/M02** and other mini printers (**ESC/POS**),
**Brother QL** & **DYMO LabelWriter** (proprietary raster), **Zebra** (ZPL/EPL — well-supported already),
and **Rollo / OFFNOVA** (TSPL, but they ship their own arm64 drivers).

## Install

```bash
git clone https://github.com/RunTheWall/hzd950-cups-driver
cd hzd950-cups-driver
sudo ./install.sh          # builds the filter, installs filter + backend + PPD, adds a "HZD950" queue
```

`install.sh` builds from source if a C compiler + CUPS headers are present; **if they're not, it downloads
a prebuilt filter binary for your CPU** from the latest release (no build tools needed). It also turns on
sharing + AirPrint and offers to print a welcome label ([`assets/welcome-card.png`](assets/welcome-card.png)).

Then print to the **HZD950** queue from anything — or add it from
[another Mac / iPhone / PC](#connect-from-another-mac--iphone--pc-no-driver-install) with no driver.

### Add our package repo (apt / dnf) — recommended

Add it once, then install and **upgrade by name** like any system package. Signed, and hosted
free on GitHub Pages — [runthewall.github.io/hzd950-cups-driver](https://runthewall.github.io/hzd950-cups-driver/).

```bash
# Debian / Ubuntu / Raspberry Pi OS
curl -fsSL https://runthewall.github.io/hzd950-cups-driver/apt/KEY.gpg \
  | sudo tee /usr/share/keyrings/hzd950.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/hzd950.gpg] https://runthewall.github.io/hzd950-cups-driver/apt ./" \
  | sudo tee /etc/apt/sources.list.d/hzd950.list
sudo apt update && sudo apt install hzd950-cups-driver
```
```bash
# Fedora / RHEL / openSUSE
sudo curl -fsSL https://runthewall.github.io/hzd950-cups-driver/rpm/hzd950.repo \
  -o /etc/yum.repos.d/hzd950.repo
sudo dnf install hzd950-cups-driver
```

### Or a one-off package download (no repo)

Every release is built by GitHub Actions for **amd64 / arm64 / armhf** — grab one from the
[**Releases**](https://github.com/RunTheWall/hzd950-cups-driver/releases/latest) page:

```bash
# Debian / Ubuntu / Raspberry Pi OS
sudo apt install ./hzd950-cups-driver_*_arm64.deb        # or _amd64 / _armhf

# Fedora / RHEL / openSUSE
sudo dnf install ./hzd950-cups-driver-*.x86_64.rpm       # or .aarch64

# Arch — build the shipped PKGBUILD directly (AUR listing pending):
git clone https://github.com/RunTheWall/hzd950-cups-driver
( cd hzd950-cups-driver/packaging/aur && makepkg -si )

# NixOS — add to your CUPS drivers
#   services.printing.drivers = [ inputs.hzd950.packages.${pkgs.system}.default ];
#   (flake input: github:RunTheWall/hzd950-cups-driver)
```

Packages install the **driver files only**. Create the queue once (or just run `./install.sh`):

```bash
sudo lpadmin -p HZD950 -E -v hzd950:auto -P /usr/share/ppd/hzd950/HZD950-PRO.ppd \
     -o printer-is-shared=true -o media=na_index-4x6_4x6in
```

Packaging sources live in [`packaging/`](packaging/) (`deb/`, `rpm/`, `aur/`) and [`flake.nix`](flake.nix).

## Two queues: crisp labels + photo/Gathering

**Print Mode** is a halftone choice, and the right one depends on content:

- **Default** (threshold) — crisp solid black; best for **text, barcodes, QR** (most shipping labels).
- **Gathering** (clustered-dot dither) — renders **greys/photos**; needed for things like a faint grey
  QR watermark that threshold would otherwise drop. The trade-off: it softens text/barcode edges.

The filter honours each queue's **PPD default**, so the clean setup is **two queues on the same
printer** — pick whichever fits the job:

```bash
# 1) crisp labels (Default / threshold)
sudo lpadmin -p HZD950 -E -v hzd950:auto -P /usr/share/ppd/hzd950/HZD950-PRO.ppd \
  -o printer-is-shared=true -o PrintMode=5 -o Darkness=8 -o PrintSpeed=50

# 2) photo / Gathering (greys, watermarks, photos)
sudo lpadmin -p HZD950-Photo -E -v hzd950:auto -P /usr/share/ppd/hzd950/HZD950-PRO.ppd \
  -o printer-is-shared=true -o PrintMode=3 -o Darkness=7 -o PrintSpeed=20
```

Because the mode is baked into the **queue default**, this works even for clients that can't show the
Print Mode menu (e.g. macOS AirPrint / IPP-Everywhere) — they just pick the right queue and the Pi
applies the rest. Option values: **PrintMode** `5`=Default `3`=Gathering `0`=None `2`=Diffusion
`4`=ErrorDiffusion · **Darkness** `0`–`15` · **PrintSpeed** = in/sec ×10 (`20`=2″/s … `60`=6″/s).

## Connect from another Mac / iPhone / PC (no driver install)

The printer renders on the Pi, so **client machines never need a driver** — they just need to reach
the shared queue. `install.sh` already turns sharing on and makes it **AirPrint-discoverable**.

- **The key server-side bit** (install.sh does this for you): CUPS advertises shares with a `_cups`
  Bonjour subtype, and the moment macOS sees `_cups` it forces a *"Generic PostScript"* driver instead
  of driverless AirPrint. Dropping it fixes the one-click add:
  ```
  BrowseDNSSDSubTypes _print,_universal      # in /etc/cups/cupsd.conf, then: sudo systemctl restart cups
  ```
- **Mac / iPhone / iPad:** open **Add Printer** → the queue now appears as **AirPrint** → pick it. Done.
  Default paper is already 4×6 (set server-side; a profile can't set it).
- **One downloadable file:** double-click [`client/RTW-HZD950-airprint.mobileconfig`](client/RTW-HZD950-airprint.mobileconfig)
  (edit the hostname first) — adds both queues, works across subnets.
- **One script (Mac):** [`client/add-printer.command`](client/add-printer.command) runs the `lpadmin … -m everywhere` for you.
- **Windows 10/11 / Linux:** they auto-discover the shared IPP printer (IPP Everywhere / Mopria) — add it driverless.

Custom options (Gathering/Darkness/Speed) don't show in a driverless client's dialog — they ride on the
**queue default** (that's why the [two-queue](#two-queues-crisp-labels--photogathering) split exists: pick HZD950 vs HZD950-Photo).

## Is my printer really TSPL? (10-second check, prints nothing)

```bash
printf '~!T\r\n' | sudo tee /dev/usb/lp0 >/dev/null   # send the model query
sudo head -c 32 /dev/usb/lp0                          # it replies with its model in ASCII
```
If it echoes back something like `HZD950-PRO`, it speaks TSPL and this driver will drive it.

## How it works

```
your app ──► CUPS ──► gstoraster ──► rastertohzd ──► TSPL ──► hzd950 backend ──► printer
                                     (this repo)               (this repo)
```

- **`rastertohzd`** (C filter): reads the CUPS raster page and emits TSPL —
  `SIZE / GAP / DENSITY / SPEED / DIRECTION / REFERENCE / CLS / BITMAP 0,0,<wbytes>,<hdots>,1,<1bpp> / PRINT`.
  The 8-bit page is flattened to 1-bit dots using the selected **Print Mode** dither.
- **`hzd950`** (shell backend): writes the TSPL straight to the printer's `usblp` character device,
  located **by USB id/serial** so it survives reboots and USB re-enumeration, and coexists with other
  USB printers without fighting the libusb backend.

Multiple USB printers? Drop in [`udev/99-hzd950.rules`](udev/99-hzd950.rules) for a stable
`/dev/usb/label-hzd950` symlink.

## Notes

- CUPS 2.4 prints a *"printer drivers are deprecated"* warning — harmless; classic PPD+filter drivers
  work for years yet. A PAPPL/Printer-Application port may come later.
- Reverse-engineered cleanly from the printer's own TSPL output. No vendor code is redistributed.

## License

MIT © Run The Wall. See [LICENSE](LICENSE). Built and maintained for free — support us by trying
**[Constly, our free Markdown editor → https://constly.com](https://constly.com)**.
