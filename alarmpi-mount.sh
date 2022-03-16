#!/bin/bash
set -ex

IMG="${1:-alarmpi.img}"
DST="${2:-alarmpi}"
CACHE="${3:-cache}"

if [ ! -d "$DST" ]; then mkdir "$DST"; fi

if [ -b "$IMG" ]; then
  parts=( "$IMG"1 "$IMG"2 )
else
  parts=( $(kpartx -av "$IMG"|cut -f3 -d ' ') )
  parts[0]=/dev/mapper/${parts[0]}
  parts[1]=/dev/mapper/${parts[1]}
fi

mount ${parts[1]} "$DST" -ocompress=zstd:15,subvol=@arch_root
mount ${parts[0]} "$DST"/boot
mount --bind "$CACHE" "$DST/var/cache/pacman"
for d in dev run proc sys; do mount --bind /$d "$DST"/$d; done
[ -d /run/systemd/resolve/ ] || mkdir -p /run/systemd/resolve
[ -f /run/systemd/resolve/resolv.conf ] || cp -L /etc/resolv.conf /run/systemd/resolve/

