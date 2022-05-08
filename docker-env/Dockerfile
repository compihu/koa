FROM archlinux:latest
RUN \
pacman -Syu --noconfirm && \
pacman -S --noconfirm base-devel git && \
git clone https://aur.archlinux.org/yay-bin.git && \
cd yay-bin && \
env EUID=1000 makepkg && \
pacman --noconfirm -U yay-bin-*.pkg.* && \
cd .. && \
rm -rf yay-bin && \
useradd -m -s /bin/bash -u 1000 build && \
echo "build ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/build

CMD /bin/bash
