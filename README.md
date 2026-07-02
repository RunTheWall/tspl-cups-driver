# HZD950-PRO — free Linux & Raspberry Pi (ARM) CUPS driver

A small, clean **CUPS driver for the HZD950-PRO / HERO 4×6 direct-thermal label printer**
(USB `0fe6:811e`, **TSPL/TSPL2**, 300 dpi) that works on **Linux and Raspberry Pi (arm64/armhf)** —
the architectures the vendor driver leaves out.

The vendor ships only x86/i386 filter binaries, so on a Raspberry Pi you hit *"there's no Linux
driver for this printer."* There is now. This one is **~150 lines of C + a tiny shell backend**,
builds natively on ARM, and gives you the printer as a normal shared CUPS queue — with Darkness,
Print Speed, offsets, and **Print Mode (including Gathering)**.

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

- **Printer:** HZD950-PRO, sold as the **HERO Shipping Label Printer** and other rebadges of the same
  300 dpi USB TSPL 4×6 label engine (`0fe6:811e`).
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

## Install

```bash
git clone https://github.com/RunTheWall/hzd950-cups-driver
cd hzd950-cups-driver
sudo ./install.sh          # builds the filter, installs filter + backend + PPD, adds a "HZD950" queue
```

`install.sh` needs a C compiler, `make`, and the CUPS dev headers. If they're missing it prints the exact
install command **for your distro** (apt / dnf / yum / pacman / zypper / apk). It also turns on sharing +
AirPrint and offers to print a welcome label ([`assets/welcome-card.png`](assets/welcome-card.png)).

Then print to the **HZD950** queue from anything — or add it from
[another Mac / iPhone / PC](#connect-from-another-mac--iphone--pc-no-driver-install) with no driver.

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
