#!/bin/bash
set -ex

. ./koa-common.sh

parse_params $@

sudo fuser -k "$WD" || true
sudo umount -R "$WD" || true
if [ ! -b "$IMG" ]; then
  sudo kpartx -d "$IMG"
fi
