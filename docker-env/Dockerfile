FROM archlinux:latest
RUN \
pacman -Syu --noconfirm;\
pacman -S --noconfirm base-devel git
COPY build-mainsail.sh /
CMD /bin/bash
