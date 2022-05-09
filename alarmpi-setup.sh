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

pacman --noconfirm -S vim mc screen pv sudo base-devel man-db parted bash-completion usbutils nginx polkit
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/wheel-nopasswd
usermod -aG wheel alarm

systemctl enable wpa_supplicant@wlan0
systemctl enable systemd-networkd

cd /root
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
env EUID=1000 makepkg
pacman --noconfirm -U yay-bin-*.pkg.*
cd /root
rm -rf yay-bin

# klipper optional dependencies
pacman --noconfirm -S python-numpy python-matplotlib

cat >/home/alarm/alarmpi-user.sh <<-EOF
	#!/usr/bin/bash
	set -ex

	yay -S --noconfirm --removemake --mflags --nocheck klipper-py3-git
	yay -S --noconfirm --removemake moonraker-git
	rm -rf .cache/yay/*
EOF
chmod a+x /home/alarm/alarmpi-user.sh
su -l -c /home/alarm/alarmpi-user.sh alarm
rm /home/alarm/alarmpi-user.sh
sed -i -E 's#(ExecStart=.*)#\1 -l /var/log/klipper/klippy.log#' /lib/systemd/system/klipper.service
pacman -U --noconfirm /root/mainsail-git*.pkg.*

cp /usr/share/doc/mainsail/mainsail-nginx.conf /etc/nginx/
cp /usr/share/doc/mainsail/mainsail-klipper.cfg /etc/klipper/
cp /usr/share/doc/moonraker/moonraker-klipper.cfg /etc/klipper/
cat >/etc/klipper/klipper.cfg <<-EOF
	# put your configuration in printer.cfg and leave this file alone
	[include moonraker-klipper.cfg]
	[include mainsail-klipper.cfg]
	[include printer.cfg]
EOF

ln -s /usr/share/klipper/examples /usr/lib/klipper/config
ln -s /usr/share/doc/klipper /usr/lib/klipper/docs

systemctl enable klipper
systemctl enable moonraker
systemctl enable nginx

echo "klipper ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *, /usr/bin/shutdown *" >/etc/sudoers.d/klipper
