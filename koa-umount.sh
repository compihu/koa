#!/bin/bash
set -ex

export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"

parse_params $@

sudo fuser -k "$WD" || true
sudo umount -R "$WD" || true
if [ ! -b "$IMG" ]; then
  sudo losetup -D "$IMG"
fi
