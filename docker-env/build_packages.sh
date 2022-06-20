#!/bin/bash
set -x
cd
yay -Syu --noconfirm
yay -S --needed --builddir /build --noconfirm --norebuild --mflags --nocheck klipper-py3-git
yay -S --needed --builddir /build --asdeps --noconfirm $(expac -Q '%o' klipper-py3-git)
yay -S --needed --builddir /build --noconfirm --norebuild --mflags --skipchecksums moonraker-git
yay -S --needed --builddir /build --noconfirm --norebuild --removemake mainsail-git

unset err
cd /build
yay -G fluidd-git
cd fluidd-git
makepkg -s --noconfirm -r || err=$?
[ ! -z "$err" ] && [ "$err" -ne 13 ] && exit $err
true
