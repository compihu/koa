#!/bin/bash
set -ex

IMG="${1:-koa.img}"
DST="${2:-koa}"

sudo fuser -k "$DST" || true
sudo umount -R "$DST" || true
if [ ! -b "$IMG" ]; then
  sudo kpartx -d "$IMG"
fi

