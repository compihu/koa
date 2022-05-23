#!/usr/bin/bash
set -ex

AH=yay
DEFAULT_UI=mainsail
TRUSTED_NET="$1"

pacman-key --init
pacman-key --populate archlinuxarm

locale-gen

pacman --noconfirm -Sy
pacman --noconfirm -S btrfs-progs
pacman --noconfirm -Su

# pacman --noconfirm -S etckeeper git
# git config --global init.defaultBranch master
# etckeeper init
# git -C /etc config user.name "EtcKeeper"
# git -C /etc config user.email "root@koa"
# etckeeper commit -m "Initial commit"

pacman --noconfirm --needed -S vim sudo base-devel git usbutils nginx polkit v4l-utils avahi
# for development purposes
pacman --noconfirm -S mc screen pv man-db bash-completion parted
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

sed -i -e 's/rw/rootflags=compress=zstd:15,subvol=@koa_root,relatime rw/' \
  -e 's/ console=serial0,115200//' \
  -e 's/ kgdboc=serial0,115200//' \
  "/boot/cmdline.txt"

tee -a "/boot/config.txt" >/dev/null <<-EOF

	[all]
	gpu_mem=16
	enable_uart=1
	dtparam=spi=on
EOF

# klipper optional dependencies
pacman --noconfirm -S python-numpy python-matplotlib

cat >/home/alarm/koa-user.sh <<-EOF
	#!/usr/bin/bash
	set -ex

	$AH -S --builddir /build --noconfirm --removemake --norebuild --mflags --nocheck klipper-py3-git
	$AH -S --builddir /build --noconfirm --removemake --norebuild moonraker-git
	$AH -S --builddir /build --noconfirm --removemake --norebuild mjpg-streamer ustreamer
EOF
chmod a+x /home/alarm/koa-user.sh
chown -R alarm:alarm /build/*
su -l -c /home/alarm/koa-user.sh alarm
rm /home/alarm/koa-user.sh
sed -E 's#(ExecStart=.*)#\1 -l /var/log/klipper/klippy.log#' /lib/systemd/system/klipper.service >/etc/systemd/system/klipper.service

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


################################################################
# Configuring Klipper & co.
################################################################
# Nginx main config
cat >/etc/nginx/nginx.conf <<-EOF
	user http;
	worker_processes  1;

	events {
	    worker_connections  1024;
	}

	http {
	    types_hash_max_size 2048;
	    include             mime.types;
	    default_type        application/octet-stream;

	    sendfile            on;
	    keepalive_timeout   65;

	    include mjpgstreamers.conf;
	    include webui.conf;
	}
EOF

# Webcam upstreams
cat >/etc/nginx/mjpgstreamers.conf <<-EOF
	upstream mjpgstreamer1 {
	    ip_hash;
	    server 127.0.0.1:8080;
	}

	upstream mjpgstreamer2 {
	    ip_hash;
	    server 127.0.0.1:8081;
	}

	upstream mjpgstreamer3 {
	    ip_hash;
	    server 127.0.0.1:8082;
	}

	upstream mjpgstreamer4 {
	    ip_hash;
	    server 127.0.0.1:8083;
	}
EOF

# Klipper main configuration file
cat >/etc/klipper/klipper.conf <<-EOF
	# put your configuration in printer.cfg and leave this file alone
	[include webui-klipper.cfg]
	[include moonraker-klipper.cfg]
	[include printer.cfg]
EOF

# copying / editing mainsail config files
ln=$(sed -n -e '/^\}$/=' /usr/share/doc/mainsail/mainsail-nginx.conf |tail -n1)
head -n $(($ln - 1)) /usr/share/doc/mainsail/mainsail-nginx.conf >/etc/nginx/mainsail-nginx.conf
cat >>/etc/nginx/mainsail-nginx.conf <<-EOF

	    location /webcam/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer1/;
	    }

	    location /webcam2/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer2/;
	    }

	    location /webcam3/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer3/;
	    }

	    location /webcam4/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer4/;
	    }
EOF
tail -n +$ln /usr/share/doc/mainsail/mainsail-nginx.conf >>/etc/nginx/mainsail-nginx.conf

cp /usr/share/doc/mainsail/mainsail-klipper.cfg /etc/klipper/


# Copying / editing fluidd config files
ln=$(sed -n -e '/^\}$/=' /usr/share/doc/fluidd/fluidd-nginx.conf |tail -n1)
head -n $(($ln - 1)) /usr/share/doc/fluidd/fluidd-nginx.conf >/etc/nginx/fluidd-nginx.conf
cat >>/etc/nginx/fluidd-nginx.conf <<-EOF
	
	    location /webcam/ {
	        proxy_pass http://mjpgstreamer1/;
	    }
	
	    location /webcam2 {
	        proxy_pass http://mjpgstreamer2/;
	    }
	
	    location /webca3/ {
	        proxy_pass http://mjpgstreamer3/;
	    }
	
	    location /webcam4/ {
	        proxy_pass http://mjpgstreamer4/;
	    }
EOF
tail -n +$ln /usr/share/doc/fluidd/fluidd-nginx.conf >>/etc/nginx/fluidd-nginx.conf

cp /usr/share/doc/fluidd/fluidd-klipper.cfg /etc/klipper/


# Copying moonraker configs and creating symlinks (instead of editing them)
cp /usr/share/doc/moonraker/moonraker-klipper.cfg /etc/klipper/
ln -s /usr/share/klipper/examples /usr/lib/klipper/config
ln -s /usr/share/doc/klipper /usr/lib/klipper/docs
# TODO: mainsail.conf editing
sed -i -e "s/^\(host:\)/\1 0.0.0.0/" \
    -e "s/^#\(\[authorization\]\)/\1/" \
    -e "s%^#\?\(trusted_clients:\)%\1\n  $TRUSTED_NET%" \
    -e "s%^#\?\(cors_domains:\)%\1\n  *.local\n  *://.app.fluidd.xyz%" \
    -e "s%^#\?\(database_path:\).*%\1 /var/lib/moonraker/db%" \
    /etc/klipper/moonraker.conf

ln -s ${DEFAULT_UI}-nginx.conf /etc/nginx/webui.conf
ln -s ${DEFAULT_UI}-klipper.cfg /etc/klipper/webui-klipper.cfg

# Registering services
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

cat >/etc/systemd/system/ustreamer@.service <<-EOF
	[Unit]
	Description=uStreamer service
	After=network.target

	[Service]
	Environment="SCRIPT_ARGS=%I"
	User=klipper
	ExecStart=/usr/bin/ustreamer --process-name-prefix ustreamer-%I --log-level 0 -d /dev/video%I --device-timeout=8 -m mjpeg -r 1920x1080 -f 30 -s 0.0.0.0 -p 808%I

	[Install]
	WantedBy=klipper.service
EOF

cat >/etc/systemd/system/webcamd.service <<-EOF
	[Unit]
	Description=the MainsailOS webcam daemon (based on OctoPi) with the user specified config

	[Service]
	WorkingDirectory=/usr/local/bin
	StandardOutput=append:/var/log/webcamd.log
	StandardError=append:/var/log/webcamd.log
	ExecStart=/usr/local/bin/webcamd
	Restart=always
	Type=forking
	User=klipper

	[Install]
	WantedBy=multi-user.target
EOF

systemctl enable klipper.service
systemctl enable klipper-mcu.service
systemctl enable moonraker.service
systemctl enable nginx.service
systemctl enable ustreamer@0.service
systemctl enable avahi-daemon

echo "klipper ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *, /usr/bin/systemctl start *, /usr/bin/systemctl stop *, /usr/bin/shutdown *" >/etc/sudoers.d/klipper
cp /build/klipper.bin /var/lib/klipper
