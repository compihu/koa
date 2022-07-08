#!/bin/bash
set -ex
cd /build
if [ -d klipper ]; then
  git -C klipper pull
else 
  git clone --depth 1 'https://github.com/Klipper3d/klipper.git'
fi
cp mcu.config klipper/.config
pushd klipper
make clean
make -j$(nproc)
cp out/klipper.bin /build/
popd

if [ -d mainsail ]; then
  git -C mainsail pull
else 
  git clone https://github.com/mainsail-crew/mainsail.git
fi
pushd mainsail
npm install --no-update-notifier --no-audit --cache "/build/npm-cache"
./node_modules/.bin/vite build
tar -C dist -caf /build/mainsail.tar.gz .
popd
