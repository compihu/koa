#!/usr/bin/bash
set -ex

pacman-key --init
pacman-key --populate archlinuxarm

locale-gen

pacman --noconfirm -Sy
pacman --noconfirm -S btrfs-progs
pacman --noconfirm -Su

pacman --noconfirm -S etckeeper git
git config --global init.defaultBranch master
etckeeper init
git -C /etc config user.name "EtcKeeper"
git -C /etc config user.email "root@alarmpi"
etckeeper commit -m "Initial commit"

pacman --noconfirm -S vim mc screen pv sudo base-devel
cd /root
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
env EUID=1 makepkg
pacman --noconfirm -U yay-bin-*.pkg.tar.xz
cd /root
rm -rf yay-bin

