#!/bin/bash
set -ex

IMG="${1:-alarmpi.img}"
DST="${1:-alarmpi}"

sudo fuser -k "$DST" || true

sudo umount -R "$DST" || true
sudo kpartx -d "$IMG"

