#!/bin/bash
set -ex
cd /usr/lib/klipper
cp /build/mcu.config .config
make -j$(nproc)
