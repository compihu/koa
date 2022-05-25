#!/bin/bash
set -ex

. ./koa-common.sh

parse_params $@

if [ ! -d "$WD" ]; then mkdir "$WD"; fi

if [ -b "$IMG" ]; then
  parts=( "$IMG"1 "$IMG"2 )
else
  parts=( $(sudo kpartx -av "$IMG"|cut -f3 -d ' ') )
  parts[0]=/dev/mapper/${parts[0]}
  parts[1]=/dev/mapper/${parts[1]}
fi

sudo mount ${parts[1]} "$WD" "-ocompress=zstd:15,subvol=${SUBVOL}"
sudo mount ${parts[0]} "$WD"/boot
sudo mount --bind "$BUILD" "$WD/build"
sudo mount --bind "$CACHE" "$WD/var/cache/pacman"
for d in dev proc sys; do sudo mount --bind /$d "$WD"/$d; done
[ -d "${WD}/run/systemd/resolve" ] || sudo mkdir -p "${WD}/run/systemd/resolve"
[ -f "${WD}/run/systemd/resolve/resolv.conf" ] || sudo cp -L /etc/resolv.conf "${WD}/run/systemd/resolve/"

