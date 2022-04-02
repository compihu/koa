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

pacman --noconfirm -S vim mc screen pv sudo base-devel man-db parted bash-completion usbutils
sed -i \
	-e "s/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/" \
	/etc/sudoers
usermod -aG wheel alarm

systemctl enable wpa_supplicant@wlan0
systemctl enable systemd-networkd

cd /root
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
env EUID=1 makepkg
pacman --noconfirm -U yay-bin-*.pkg.tar.xz
cd /root
rm -rf yay-bin

cat >/home/alarm/alarmpi-user.sh <<-EOF
	#!/usr/bin/bash
	set -ex

	yay -S --noconfirm --removemake octoprint-venv
	yay -S --noconfirm --removemake --mflags --nocheck klipper-py3-git
EOF
chmod a+x /home/alarm/alarmpi-user.sh
su -l -c /home/alarm/alarmpi-user.sh alarm
rm /home/alarm/alarmpi-user.sh
systemctl enable octoprint
echo "octoprint ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart octoprint, /usr/bin/shutdown -r now, /usr/bin/shutdown -h now" >/etc/sudoers.d/octoprint
