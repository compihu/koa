#!/bin/bash
set -ex

export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"

parse_userdir $@
parse_params $@

if [ ! -d "$WD" ]; then mkdir "$WD"; fi

if [ -b "$IMG" ]; then
  parts=( "$IMG"1 "$IMG"2 )
else
  loopdev=( $(sudo losetup --find --show --partscan "$IMG") )
  parts=( "${loopdev}p1" "${loopdev}p2" )
fi

if [ -z "${USE_EXT4}" ]; then
  sudo mount ${parts[1]} "${WD}" "-ocompress=zstd:15,subvol=${SUBVOL}"
  sudo mount ${parts[1]} "${WD}/mnt/fs_root" "-osubvolid=0"
else
  sudo mount ${parts[1]} "${WD}"
fi
sudo mount ${parts[0]} "${WD}/boot"
[ -d "${WD}/build" ] && [ -d "${BUILDDIR}" ] && sudo mount --bind "${BUILDDIR}" "${WD}/build"
[ -d "$WD/var/cache/apk" ] && [ -d "${CACHE}" ] && sudo mount --bind "${CACHE}" "${WD}/var/cache/apk"
for dir in dev proc sys run tmp; do [ -d "${WD}/${dir}" ] && sudo mount --bind "/${dir}" "${WD}/${dir}"; done
sudo cp /etc/resolv.conf "${WD}/etc/resolv.conf"
