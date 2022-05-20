#!/usr/bin/bash
set -ex

AH=yay

pacman-key --init
pacman-key --populate archlinuxarm

locale-gen

pacman --noconfirm -Sy
pacman --noconfirm -S btrfs-progs
pacman --noconfirm -Su

pacman --noconfirm -S git
# git config --global init.defaultBranch master
# etckeeper init
# git -C /etc config user.name "EtcKeeper"
# git -C /etc config user.email "root@alarmpi"
# etckeeper commit -m "Initial commit"

pacman --noconfirm -S vim sudo base-devel usbutils nginx polkit v4l-utils parted
# for development purposes
pacman --noconfirm -S mc screen pv man-db bash-completion
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/wheel-nopasswd
usermod -aG wheel alarm

systemctl enable wpa_supplicant@wlan0
systemctl enable systemd-networkd

sed -i -e 's/#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" /etc/makepkg.conf

cd /root
git clone https://aur.archlinux.org/$AH-bin.git
cd $AH-bin
env EUID=1000 makepkg
pacman --noconfirm -U $AH-bin-*.pkg.*
cd /root
rm -rf $AH-bin

# klipper optional dependencies
pacman --noconfirm -S python-numpy python-matplotlib

cat >/home/alarm/alarmpi-user.sh <<-EOF
	#!/usr/bin/bash
	set -ex

	$AH -S --builddir /build --noconfirm --removemake --norebuild --mflags --nocheck klipper-py3-git
	$AH -S --builddir /build --noconfirm --removemake --norebuild moonraker-git
	$AH -S --builddir /build --noconfirm --removemake --norebuild mjpg-streamer ustreamer
	#$AH -S --builddir /build --noconfirm --removemake --norebuild mainsail-git
EOF
chmod a+x /home/alarm/alarmpi-user.sh
chown -R alarm:alarm /build/*
su -l -c /home/alarm/alarmpi-user.sh alarm
rm /home/alarm/alarmpi-user.sh

pacman -U --noconfirm $(ls -t /build/mainsail-git/*-any.pkg.tar.* | head -n1)
pacman -U --noconfirm $(ls -t /build/fluidd-git/*-any.pkg.tar.* | head -n1)

cat >/var/lib/klipper/build_rpi_mcu.sh <<-EOF
	#!/usr/bin/bash
	set -ex
	cd /usr/lib/klipper
	cp /build/klipper_rpi.config .config
	make -j$(nproc)
EOF
chmod a+x /var/lib/klipper/build_rpi_mcu.sh
su -l -s /bin/bash -c /var/lib/klipper/build_rpi_mcu.sh klipper
rm /var/lib/klipper/build_rpi_mcu.sh

pushd /var/lib/klipper/
cd /usr/lib/klipper
make flash
popd

usermod -a -G tty,video,audio klipper

cat >/etc/systemd/system/klipper.service <<-EOF
	[Unit]
	Description=3D printer firmware with motion planning on the host
	After=network.target
	Before=moonraker.service
	Wants=systemd-udev.service

	[Install]
	WantedBy=multi-user.target

	[Service]
	Type=simple
	User=klipper
	RemainAfterExit=no
	Environment=PYTHONUNBUFFERED=1
	#ExecStartPre=/usr/bin/sleep 3
	ExecStart=/usr/bin/python /usr/lib/klipper/klippy/klippy.py /etc/klipper/klipper.cfg -I /run/klipper/sock -a /run/klipper/ud_sock -l /var/log/klipper/klippy.log
	Restart=always
	RestartSec=10
EOF

cat >/etc/systemd/system/klipper-mcu.service <<-EOF
	[Unit]
	Description=Klipper MCU on Raspberry Pi
	After=local-fs.target
	Before=klipper.service

	[Install]
	WantedBy=klipper.service

	[Service]
	Type=simple
	ExecStart=/usr/local/bin/klipper_mcu -r
	Restart=always
	RestartSec=10
EOF

cp /usr/share/doc/mainsail/mainsail-nginx.conf /etc/nginx/
cp /usr/share/doc/mainsail/mainsail-klipper.cfg /etc/klipper/
cp /usr/share/doc/fluidd/fluidd-nginx.conf /etc/nginx/
cp /usr/share/doc/fluidd/fluidd-klipper.cfg /etc/klipper/
cp /usr/share/doc/moonraker/moonraker-klipper.cfg /etc/klipper/

ln -s /usr/share/klipper/examples /usr/lib/klipper/config
ln -s /usr/share/doc/klipper /usr/lib/klipper/docs

systemctl enable klipper
systemctl enable klipper-mcu
systemctl enable moonraker
systemctl enable nginx

echo "klipper ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *, /usr/bin/shutdown *" >/etc/sudoers.d/klipper
cp /build/klipper.bin /var/lib/klipper
