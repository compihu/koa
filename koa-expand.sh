#!/bin/bash
set -ex

. ./koa-common.sh

parse_params $@

if [ ! -b "${IMG}" ]; then
  echo "Input is not a block device!"
  exit 1
fi

[ -d "${WD}" ] || mkdir "${WD}"

sudo parted --script "${IMG}" resizepart 2 100%

sudo mount "${IMG}2" "${WD}"
sudo btrfs filesystem resize max "${WD}"
sudo umount --recursive "${WD}"
