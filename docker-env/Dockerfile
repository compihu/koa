FROM alpine:latest

RUN adduser -D klipper && adduser klipper wheel && \
    apk update && apk add sudo bash && \
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/wheel-nopasswd 
RUN apk add gcc musl-dev linux-headers make gcc-arm-none-eabi newlib-arm-none-eabi python3 python3-dev git vim curl
RUN curl -s https://bootstrap.pypa.io/get-pip.py | python3


# pacman -S --noconfirm base-devel git arm-none-eabi-gcc expac && \
# sed -i -e 's/#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" /etc/makepkg.conf && \
# useradd -m -s /bin/bash -u 1000 build && \
# echo "build ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/build
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
