#!/bin/bash
set -ex
chmod 777 /build
cd /build
if [ -d klipper ]; then git -C klipper pull
else  git clone --depth 1 https://github.com/Klipper3d/klipper.git; fi
cp mcu.config klipper/.config
cd klipper
make clean
make -j$(nproc)
cp out/klipper.bin ../
