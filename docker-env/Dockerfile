FROM archlinux:latest

RUN pacman-key --init && pacman-key --populate archlinux
RUN \
pacman -Syu --noconfirm && \
pacman -S --noconfirm base-devel git arm-none-eabi-gcc arm-none-eabi-newlib python3 && \
useradd -m -s /bin/bash -u 1000 build && \
echo "build ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/build
# RUN \
# pushd /root/ && \
# git clone https://aur.archlinux.org/yay-bin.git && \
# pushd yay-bin && \
# env EUID=1000 makepkg && \
# pacman --noconfirm -U yay-bin-*.pkg.* && \
# popd && \
# rm -rf yay-bin && \
# popd
# RUN \
# pushd /root/ && \
# git clone https://aur.archlinux.org/pikaur.git && \
# pushd pikaur && \
# env EUID=1000 makepkg -s --noconfirm -r && \
# pacman --noconfirm -U pikaur-*.pkg.* && \
# popd && \
# rm -rf pikaur && \
# popd
CMD /bin/bash
