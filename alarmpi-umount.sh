#!/bin/bash
set -ex

IMG="${1:-alarmpi.img}"
DST="${2:-alarmpi}"

sudo fuser -k "$DST" || true
sudo umount -R "$DST" || true
if [ ! -b "$IMG" ]; then
  sudo kpartx -d "$IMG"
fi

