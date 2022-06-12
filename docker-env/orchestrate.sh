#!/bin/bash
set -ex
chmod 777 /build
su -l build -c /env/build_packages.sh
su -l klipper -s /bin/bash -c /env/build_mcu.sh
cp /usr/lib/klipper/out/klipper.bin /build/
