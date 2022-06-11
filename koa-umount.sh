#!/bin/bash
set -ex

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTPATH}/koa-common.sh"

parse_params $@

sudo fuser -k "$WD" || true
sudo umount -R "$WD" || true
if [ ! -b "$IMG" ]; then
  sudo losetup -D "$IMG"
fi
