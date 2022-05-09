#!/bin/sh
set -x
[ -d build ] || mkdir build
cd /build
git clone https://aur.archlinux.org/mainsail-git.git
cd mainsail-git
env EUID=1000 makepkg -sr --noconfirm
mv mainsail-git*.pkg.* ../
cd ../
rm -rf mainsail-git
