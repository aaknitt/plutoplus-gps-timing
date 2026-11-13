# GuardPolice / plutoplus-gps-timing LibreSDR SD bring-up image

## Source

- FPGA + Linux + ramdisk + DTB: extracted from
  https://github.com/lgarrido581/plutoplus-gps-timing/releases/download/v2.0.4/libre.frm
- FSBL + U-Boot: hz12opensource/libresdr v0.38 baseclock_cpu750_ddr525
- BOOT.bin rebuilt with open-source Xilinx bootgen

**THIS IS NOT a Tezuka sdimg.** Do not mix with Tezuka files on the same card.

## How to flash

1. Keep your known-good Tezuka SD as recovery.
2. Format a SEPARATE microSD as FAT32.
3. Copy EVERYTHING from the assembled SD directory to the card root
   (`BOOT.bin`, `uImage`, `devicetree.dtb`, `uramdisk.image.gz`, `uEnv.txt`, …).
4. Insert card, power the board (SD boot).
5. Serial console: 115200 8N1 on the debug USB-UART.
6. Network: often `192.168.2.1` (USB) or check Ethernet DHCP/static.
7. SSH: `root` / `analog`

After boot, verify GPS-timing image:

```bash
cat /etc/gps-timing-board          # expect BOARD=libresdr
ls -l /dev/pps0
# ping via ZMQ later: pluto_ctld on :5562
```

## Wiring (LibreSDR)

Stock v2.0.4 image:

- GPS PPS → EXT_GPIO0 (**G15**) [CN1 pin 1 — not the front-panel MMCX until remapped]
- GPS TX → EXT_GPIO1 (**K14**)
- optional 10 MHz → front 10 MHz connector for frequency discipline

Branch `libresdr-mmcx-pps` remaps PPS to front MMCX / **K18** / LVCMOS25 — see
[`WINDOWS_MMCX_PPS_BITSTREAM_PLAN.md`](WINDOWS_MMCX_PPS_BITSTREAM_PLAN.md).

Do **NOT** flash QSPI until SD smoke tests pass. `libre.frm` may be included on
the card only for a later, deliberate QSPI promotion.

## Known bring-up notes (HamGeek / LibreSDR Rev.5)

- The kernel extracted from `libre.frm` is a raw zImage; `uImage` on a working
  card must be re-wrapped with `mkimage` so plain `run sdboot` works. If you
  still have an older card copy that fails with "Wrong Image Format for bootm",
  re-copy `uImage` (or from U-Boot: `bootz` after loading the three images).
- On first lab boot we saw: GPS-timing v2.0.4 services up (`/dev/pps0`,
  `pluto_ctld`), but RX ADC probe failed
  (`ad9361_dig_tune_delay: Tuning RX FAILED`). That blocks IQ capture until
  LVDS/RX is sorted — PHY/TX DDS may still show in `iio_info`. A clean sdboot
  later cleared the dig_tune failure.
