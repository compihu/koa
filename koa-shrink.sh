#!/bin/bash
set -ex

export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"

parse_params $@

if [ ! -f "${IMG}" ]; then
  echo "Input is not a regular file!"
  exit 1
fi

[ -d "${WD}" ] || mkdir "${WD}"

loopdev=( $(sudo losetup --find --show --partscan "${IMG}") )
parts=( "${loopdev}p1" "${loopdev}p2" )

sudo mount ${parts[1]} "${WD}"

while sudo btrfs filesystem resize -100M "${WD}"; do true; done
while sudo btrfs filesystem resize -10M "${WD}"; do true; done
#btrfs filesystem resize +100M "${WD}"

fssize=$(($(df -hk "${WD}"|tail -n 1 | awk '{print $2}')/1024))

sudo umount --recursive "${WD}"
losetup --detach-all "${IMG}"

partstart=$(sudo parted -m "${IMG}" unit B print | tail -n 1 | sed 's/B//g' | cut -d: -f2)
partend=$((${partstart}/1024/1024+"${fssize}"))
sudo parted --script "${IMG}" rm 2
truncate --size "${partend}MiB" "${IMG}"
sudo parted --script "${IMG}" mkpart primary btrfs "${partstart}B" 100%