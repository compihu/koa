#!/bin/bash
set -ex

IMG="${1:-koa.img}"
DST="${2:-koa}"
CACHE="${3:-cache}"
BUILD="${4:-build}"

if [ ! -d "$DST" ]; then mkdir "$DST"; fi

if [ -b "$IMG" ]; then
  parts=( "$IMG"1 "$IMG"2 )
else
  parts=( $(sudo kpartx -av "$IMG"|cut -f3 -d ' ') )
  parts[0]=/dev/mapper/${parts[0]}
  parts[1]=/dev/mapper/${parts[1]}
fi

sudo mount ${parts[1]} "$DST" -ocompress=zstd:15,subvol=@arch_root
sudo mount ${parts[0]} "$DST"/boot
sudo mount --bind "$BUILD" "$DST/build"
sudo mount --bind "$CACHE" "$DST/var/cache/pacman"
for d in dev run proc sys; do sudo mount --bind /$d "$DST"/$d; done
[ -d /run/systemd/resolve/ ] || sudo mkdir -p /run/systemd/resolve
[ -f /run/systemd/resolve/resolv.conf ] || sudo cp -L /etc/resolv.conf /run/systemd/resolve/

