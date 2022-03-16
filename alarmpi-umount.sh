#!/bin/bash
set -ex

IMG="${1:-alarmpi.img}"
DST="${1:-alarmpi}"

umount -R "$DST"
kpartx -d "$IMG"

