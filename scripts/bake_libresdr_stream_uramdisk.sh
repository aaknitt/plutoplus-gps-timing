#!/bin/bash
# Patch output/libresdr-sd ramdisk with a drop-in pluto_ctld (+ PPS-only
# S70xocorrect) and wrap uramdisk.
#
# CRITICAL: the cpio MUST record uid/gid 0. Packing as the host user (e.g. 1000)
# leaves busybox setuid-to-1000; at boot /init runs as non-root, mounts fail
# ("you must be root"), USB gadget never binds, and the host sees no RNDIS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SD="${1:-$ROOT/output/libresdr-sd}"
DROPIN="${2:-$ROOT/output/libresdr-stream-dropin/pluto_ctld-v2.2.0}"
WORKDIR="${TMPDIR:-/tmp}/libresdr-ramdisk-bake-$$"

test -f "$DROPIN" || { echo "missing drop-in binary: $DROPIN" >&2; exit 1; }
test -f "$SD/ramdisk.image.gz" || { echo "missing $SD/ramdisk.image.gz" >&2; exit 1; }
command -v mkimage >/dev/null

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/root"
cd "$WORKDIR/root"

# Device nodes may fail to recreate as non-root; empty /dev is fine (devtmpfs).
gzip -dc "$SD/ramdisk.image.gz" | cpio -idm --no-preserve-owner 2>/dev/null || true
test -x usr/bin/pluto_ctld
test -x bin/busybox
test -f opt/vfat.img

if [ ! -f usr/bin/pluto_ctld.v2.0.4.bak ]; then
  cp -a usr/bin/pluto_ctld usr/bin/pluto_ctld.v2.0.4.bak
fi
cp -f "$DROPIN" usr/bin/pluto_ctld
chmod 755 usr/bin/pluto_ctld
chmod 4755 bin/busybox
strings usr/bin/pluto_ctld | grep -q stream_start

# PPS-only labs: do not block xo_correct on chrony Leap Normal (needs on-SDR NMEA).
mkdir -p etc/init.d
cat > etc/init.d/S70xocorrect <<'EOF'
#!/bin/sh
# Frequency lock needs PPS latch only; do not wait on chrony (needs NMEA/TOD).
PIDFILE=/var/run/xocorrect.pid
case "$1" in
 start)
  (
   while :; do
    [ "$(devmem 0x7C460008 32 2>/dev/null)" = "0x00000001" ] && break
    sleep 5
   done
   exec sh /usr/bin/xo_correct.sh >>/var/log/xocorrect.log 2>&1
  ) &
  echo $! > "$PIDFILE"
  ;;
 stop) [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE" ;;
 restart) "$0" stop; "$0" start ;;
esac
EOF
chmod 755 etc/init.d/S70xocorrect
if grep -q 'chronyc tracking' etc/init.d/S70xocorrect; then
  echo "ERROR: S70xocorrect still waits on chrony" >&2
  exit 1
fi

cd "$WORKDIR"
# -R 0:0 is mandatory — do not omit.
( cd root && find . | cpio -o -H newc -R 0:0 ) > root.cpio
gzip -9 -c root.cpio > ramdisk.image.gz
mkimage -A arm -T ramdisk -C gzip -n 'gps-timing-stream' \
  -d ramdisk.image.gz uramdisk.image.gz

# Gate: refuse to install a non-root-owned busybox (the failure mode we hit).
BB_LINE="$(gzip -dc ramdisk.image.gz | cpio -tvn 2>/dev/null | grep -E '^-.* bin/busybox$' || true)"
echo "busybox cpio entry: $BB_LINE"
echo "$BB_LINE" | grep -Eq '[[:space:]]0[[:space:]]+0[[:space:]]' || {
  echo "ERROR: bin/busybox is not uid/gid 0 in the new cpio — aborting" >&2
  exit 1
}

cp -f ramdisk.image.gz "$SD/ramdisk.image.gz"
cp -f uramdisk.image.gz "$SD/uramdisk.image.gz"
ls -l "$SD/ramdisk.image.gz" "$SD/uramdisk.image.gz"
echo "BAKE_OK — copy both .gz files to the boot SD FAT root, then reboot"
