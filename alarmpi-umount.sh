#!/bin/bash
set -ex

IMG="${1:-alarmpi.img}"
DST="${1:-alarmpi}"

sudo umount -R "$DST"
sudo kpartx -d "$IMG"

