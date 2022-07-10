#!/usr/bin/bash
set -ex

. /tmp/environment
sudo pacman --noconfirm --needed -S packagekit
